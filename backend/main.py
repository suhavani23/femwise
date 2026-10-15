from food_config import (NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, CHROMA_DB_PATH, COLLECTION_NAME, OLLAMA_API_BASE_URL, OLLAMA_MODEL_NAME_EXTRACTION)
from food_security import configure_food_api
from account_api import current_user
from food_llm import generate_text
import re  # Import the regular expression module for pattern matching, used in 'inject_concentration_risk'.
import time  # Import the time module for time-related functions, specifically used for rate limiting API calls.
from fastapi import Depends, FastAPI, HTTPException  # Import FastAPI for building the web API and HTTPException for error handling.
from pydantic import BaseModel, Field
import os  # Import the os module for interacting with the operating system, though not directly used in this specific snippet.
import json  # Import the json module for working with JSON data, though not directly used for parsing in this snippet.
import ollama  # Import the Ollama client library for interacting with local LLMs (like for ingredient extraction).
from neo4j import GraphDatabase  # Import GraphDatabase from neo4j for connecting to and querying a Neo4j graph database.
import difflib  # Import difflib for calculating sequence similarities, used to find similar ingredient names.
import ast  # Import ast (Abstract Syntax Trees) for safely evaluating strings containing Python literal structures, like lists from LLM output.
import logging  # Import logging for logging messages, used for debugging database connections.

# --- Initialize FastAPI App ---
app = FastAPI()
configure_food_api(app)

# --- Configure Ollama Model ---
# Ensure Ollama server is running at this address

# Initialize the Ollama client
ollama_client = ollama.Client(host=OLLAMA_API_BASE_URL)

# --- Configure Neo4j Connection ---


driver = None  # Initialize driver globally to be set upon startup.

# Enable debug logging for Neo4j
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("neo4j")

@app.on_event("startup")
async def startup_db_client():
    """Connect to Neo4j on FastAPI startup."""
    global driver
    try:
        # Create a Neo4j driver instance
        driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USERNAME, NEO4J_PASSWORD))
        # Verify connectivity by running a simple query
        driver.verify_connectivity()
        with driver.session() as session:
            if session.run("MATCH (i:Ingredient) RETURN count(i) AS count").single()["count"] == 0:
                raise RuntimeError("Import the ingredient knowledge graph before starting food analysis.")
        print("\n" + "="*50)
        print("Successfully connected to Neo4j!")
        print(f"Neo4j Server Info: {driver.get_server_info()}")
        print("="*50 + "\n")
    except Exception as e:
        print(f"\n!!! Failed to connect to Neo4j: {e} !!!\n")
        raise RuntimeError('Packaged food requires a reachable, populated Neo4j database.') from e

@app.on_event("shutdown")
async def shutdown_db_client():
    """Close Neo4j connection on FastAPI shutdown."""
    if driver:
        driver.close()
        print("\nNeo4j connection closed.\n")

# --- Pydantic Model for Request ---
class TextExtractionRequest(BaseModel):
    text: str = Field(min_length=1, max_length=20000)

# --- Helper Functions for Neo4j Interaction ---

def get_similarity_ratio(s1: str, s2: str) -> float:
    """Calculates a similarity ratio between two strings (0.0 to 1.0) using difflib."""
    return difflib.SequenceMatcher(None, s1.lower(), s2.lower()).ratio()

def find_ingredient_in_neo4j(tx, ingredient_name: str) -> dict | None:
    """
    Finds an exact ingredient by name, or the most similar one if no exact match.
    Returns a dictionary of matched properties (name, effects, verdict, classification, match_type) or None.
    """
    try:
        print(f"\n{'='*30} Neo4j Query {'='*30}")
        print(f"Searching for ingredient: '{ingredient_name}'")

        # --- 1. Try exact match first ---
        query_exact = """
        MATCH (i:Ingredient)
        WHERE toLower(i.name) = toLower($ingredient_name)
        OPTIONAL MATCH (i)-[:HAS_EFFECT]->(e:Effect)
        OPTIONAL MATCH (i)-[:HAS_VERDICT]->(v:Verdict)
        OPTIONAL MATCH (i)-[:HAS_CLASSIFICATION]->(c:Classification) // <--- ADDED THIS LINE
        RETURN
            i.name AS name,
            collect(DISTINCT e.description) AS effect_description,
            collect(DISTINCT v.value) AS verdict_value,
            c.text AS classification_value // <--- MODIFIED THIS LINE to fetch from the Classification node
        LIMIT 1
        """
        exact_result = tx.run(query_exact, ingredient_name=ingredient_name).single()

        if exact_result:
            effects = exact_result["effect_description"] or []
            verdicts = exact_result["verdict_value"] or []
            # Retrieve classification from c.text
            classification = exact_result["classification_value"]

            matched_data = {
                "name": exact_result["name"],
                "effects": ", ".join(effects),
                "verdict": ", ".join(verdicts),
                "classification": classification, # <--- Will now correctly get from 'c.text'
                "is_exact_match": True,
                "match_type": "(exact match found)"
            }

            print(f"\n✅ EXACT MATCH for '{ingredient_name}': {matched_data['name']}")
            print(f"    Effects: {matched_data['effects']}")
            print(f"    Verdict: {matched_data['verdict']}")
            print(f"    Classification (raw from DB): {matched_data['classification']}")
            print(f"{'='*70}\n")
            return matched_data

        # --- 2. No exact match -> find similar ingredients ---
        print(f"\n🔍 No exact match found. Searching for similar ingredients to '{ingredient_name}'...")

        query_all_ingredients = "MATCH (i:Ingredient) RETURN i.name AS name"
        all_db_ingredients = [record["name"] for record in tx.run(query_all_ingredients)]

        if not all_db_ingredients:
            print("⚠️ No ingredients found in the database")
            return None

        # --- Find best similar match ---
        best_match_name = None
        highest_similarity = 0.0
        SIMILARITY_THRESHOLD = 0.65

        for db_ing in all_db_ingredients:
            similarity = get_similarity_ratio(ingredient_name, db_ing)
            if similarity > highest_similarity and similarity >= SIMILARITY_THRESHOLD:
                highest_similarity = similarity
                best_match_name = db_ing

        if best_match_name:
            print(f"\n✅ CLOSEST MATCH: '{best_match_name}' (similarity: {highest_similarity:.2f})")

            query_similar = """
            MATCH (i:Ingredient {name: $best_match_name})
            OPTIONAL MATCH (i)-[:HAS_EFFECT]->(e:Effect)
            OPTIONAL MATCH (i)-[:HAS_VERDICT]->(v:Verdict)
            OPTIONAL MATCH (i)-[:HAS_CLASSIFICATION]->(c:Classification) // <--- ADDED THIS LINE
            RETURN
                i.name AS name,
                collect(DISTINCT e.description) AS effect_description,
                collect(DISTINCT v.value) AS verdict_value,
                c.text AS classification_value // <--- MODIFIED THIS LINE to fetch from the Classification node
            LIMIT 1
            """
            similar_result = tx.run(query_similar, best_match_name=best_match_name).single()

            if similar_result:
                effects = similar_result["effect_description"] or []
                verdicts = similar_result["verdict_value"] or []
                # Pass the raw classification string directly from Neo4j, allow None
                classification = similar_result["classification_value"]

                matched_data = {
                    "name": similar_result["name"],
                    "effects": ", ".join(effects),
                    "verdict": ", ".join(verdicts),
                    "classification": classification, # <--- Will now correctly get from 'c.text'
                    "is_exact_match": False,
                    "match_type": f"(similar match to '{ingredient_name}')"
                }

                print(f"    Effects: {matched_data['effects']}")
                print(f"    Verdict: {matched_data['verdict']}")
                print(f"    Classification (raw from DB): {matched_data['classification']}")
                print(f"{'='*70}\n")
                return matched_data
            else:
                print(f"\n❌ Could not retrieve details for similar match: '{best_match_name}'")
                return None
        else:
            print(f"\n❌ No similar match found (threshold: {SIMILARITY_THRESHOLD})")
            return None

    except Exception as e:
        print(f"\n❌ ERROR in Neo4j query: {e}")
        return None


# --- Function for LLM Ingredient Extraction using Ollama ---
async def call_llm_for_ingredient_extraction(raw_text: str) -> list[str]:
    """
    Calls the Ollama LLM to extract and normalize ingredients from raw text.
    """
    print(f"\n{'='*30} LLM Processing {'='*30}")
    print(f"Input text: {raw_text[:100]}...")

    prompt_content = (
        f"Extract all food ingredients from the following text. "
        f"Return the ingredients as a Python-like list of strings, with each ingredient normalized. "
        f"Ensure the output is *only* the Python list and nothing else.\n\n"
        f"Text: \"\"\"{raw_text}\"\"\"\n\n"
        f"Extracted Ingredients (Python list):"
    )

    try:
        response = ollama_client.chat(
            model=OLLAMA_MODEL_NAME_EXTRACTION,
            messages=[
                {'role': 'system', 'content': 'You are an expert food ingredient extractor. Only output valid Python lists.'},
                {'role': 'user', 'content': prompt_content},
            ],
            options={'temperature': 0.1},
            stream=False
        )

        llm_output = response['message']['content'].strip()
        print(f"\nLLM Raw Output:\n{llm_output}")

        try:
            if llm_output.startswith('[') and llm_output.endswith(']'):
                extracted_list = ast.literal_eval(llm_output)
            else:
                print("⚠️ LLM output format unexpected. Attempting fallback parsing.")
                extracted_list = [item.strip() for item in llm_output.split(',') if item.strip()]

            extracted_list = [str(item).lower() for item in extracted_list]
            extracted_list = list(dict.fromkeys(extracted_list))

            print(f"\n✅ Final Extracted Ingredients: {extracted_list}")
            print(f"{'='*70}\n")
            return extracted_list

        except (ValueError, SyntaxError) as e:
            print(f"\n❌ Error parsing LLM output: {e}")
            return []

    except Exception as e:
        print(f"\n❌ Error calling Ollama: {e}")
        return []

<<<<<<< HEAD
# --- Generative Model Setup (from your existing LLM script) ---
GEMINI_API_KEYS = [k.strip() for k in os.environ.get("GEMINI_API_KEYS", "").split(",") if k.strip()] or [""]  # Comma-separated keys from the environment

current_key_index = 0
current_api_key = GEMINI_API_KEYS[current_key_index]
genai.configure(api_key=current_api_key)

# --- Generative Model Setup ---
model = genai.GenerativeModel('gemini-1.5-flash')

=======
>>>>>>> f1cfbd8 (feat(ai): integrate OpenAI Chat completions with Gemini fallback and local Ollama extraction)
# --- NEW: LLM Function for Precise Classification ---
async def get_precise_classification_from_llm(raw_classification_text: str | None) -> str:
    if not raw_classification_text or raw_classification_text.strip().lower() == "unknown":
        return "unknown"
    prompt = ("Classify this ingredient description for PCOS relevance. "
              "Reply with exactly one word: good, bad, moderate, or unknown.\n"
              + raw_classification_text)
    result = generate_text(prompt, temperature=0.0, max_output_tokens=128).strip().lower()
    return result if result in {"good", "bad", "moderate", "unknown"} else "unknown"

# MODIFIED SYSTEM PROMPT: Adjusted to expect concise classification
SYSTEM_PROMPT = """
You are an expert AI assistant for a PCOS-focused nutrition app. Your task is to analyze ingredient information from a food product and provide a clear, concise, and helpful verdict and explanation for women with PCOS.

---
## Strict Rules to Follow:

1.   **Verdict Determination (Strictly Based on Provided Data):**
    * **CRITICAL: Your entire analysis, including the verdict and explanation, MUST exclusively use the 'Effect', 'Related To', 'PCOS Relevance', and 'Classification' provided for each ingredient in the input. DO NOT introduce external knowledge, general assumptions about ingredients, or information not explicitly stated in the provided data.**
    * **CRITICAL: The 'Classification' field for each ingredient in the input will be a concise term ('good', 'bad', 'moderate', or 'unknown') that has already been precisely determined for you. You MUST strictly use this classification when evaluating the ingredient's impact on PCOS.**
    * If the provided data classifies an ingredient in an unexpected way (e.g., 'Sugar' is classified as 'good' due to a specific context), you MUST strictly follow that classification.
    * If any ingredient classified as 'bad' (or 'potentially bad if processed' which maps to 'moderate') has a **'High' or 'Moderate' Concentration Risk**, the Verdict should be "Potentially Harmful" or "Harmful".
    * If there are multiple 'bad' ingredients, especially at 'High' or 'Moderate' risk, lean towards "Harmful".
    * **NEW RULE: If "bad" ingredients are present and constitute more than half of the total ingredients, regardless of their Concentration Risk (though still considering it), the Verdict should lean towards "Potentially Harmful" or "Harmful". This is especially true if these "bad" ingredients are prominently listed in the latter half of the ingredient list.**
    * If 'good' ingredients are prominent and 'bad' ingredients are only 'Low' risk or absent, the Verdict should be "Safe" or "Generally Recommended".
    * **Only use "Uncertain" if the provided information is genuinely contradictory *within its own definitions* or if effects are explicitly stated as uncertain *in the input*. Do not use "Uncertain" due to missing information not present in the input or from your external knowledge.**
    * Prioritize the impact of "bad" ingredients, especially those with "High" or 'Moderate' Concentration Risk, as they often outweigh beneficial ingredients.

2.   **Explanation Content:**
    * Start by directly addressing the most impactful ingredients (both good and bad), focusing on those with **'High' or 'Moderate' Concentration Risk.**
    * Clearly state *why* each relevant ingredient is good/bad, using only the provided "Effect" and "PCOS Relevance" from the input. Always link these effects directly to PCOS symptoms (e.g., "contributing to insulin resistance and inflammation").
    * Explain how the overall combination of ingredients leads to the given verdict.
    * Be concise but comprehensive.

3.   **Output Format (Strict):**
    ```
    Verdict: [Your Verdict]
    Explanation: [Your detailed explanation based on rules above]
    ```
4 . NOTE & MUST FOLLOW : YOU MUST GIVE THE EXPLANATION ONLY IN NEW LINES (points) LIKE THE LINES IN JSON FORMAT (NO PARAGRAPHS)

5. lastly give a conclusion for those ingredint the sub topic of that shuld be conclusion : 

6. MUST NOTE : keep the explanation short(but not verry short- a medium sized content) and clear to the point 
7. dont add " * " these and also dont add "-" this before the new point just begining in a new line is enough
---
## Example Output:

"Verdict: Potentially Harmful\\nExplanation: This product contains Refined Sugar in a high concentration, which is directly linked to exacerbating insulin resistance and inflammation, significant concerns for women with PCOS. While Curcumin is also present in a high concentration and offers direct beneficial effects for insulin sensitivity and hormonal balance, and Whole Grains are a good source of fiber for blood sugar regulation at a moderate concentration, the prominent presence of a highly problematic ingredient like Refined Sugar outweighs these benefits. Additionally, Soy, present in a low concentration, has a complex and potentially varied effect on hormonal balance due to phytoestrogens. Given the high concentration of refined sugar, this product is potentially harmful for women with PCOS despite the presence of beneficial ingredients. Avoiding high concentrations of refined sugars is crucial for managing PCOS symptoms."
"""

# --- Rate Limiting Parameters ---
MAX_REQUESTS_PER_MINUTE = 25
TIME_WINDOW = 60  # seconds

request_timestamps = []  # To store the timestamps of each request



def generate_model_content(user_content_str):
    return generate_text(SYSTEM_PROMPT + "\n\n" + user_content_str)

def inject_concentration_risk(user_content):
    """
    Parses the user content, calculates Concentration Risk for each ingredient
    based on its position, and injects this information into the content string.
    """
    ingredient_info_start = user_content.find("--- Ingredient Information ---")
    ingredient_info_end = user_content.find("--- End Ingredient Information ---")

    if ingredient_info_start == -1 or ingredient_info_end == -1:
        return user_content  # Return original if markers not found

    # Extract the full ingredient information block
    info_section = user_content[ingredient_info_start : ingredient_info_end]

    # Extract Total number of ingredients
    total_ingredients_match = re.search(r"Total number of ingredients:\s*(\d+)", info_section)
    if not total_ingredients_match:
        return user_content  # Cannot process without total count

    total_ingredients = int(total_ingredients_match.group(1))
    if total_ingredients == 0:
        pass

    raw_ingredient_blocks = re.split(r"(Ingredient:)", info_section)

    ingredient_contents = []
    for i in range(len(raw_ingredient_blocks)):
        if raw_ingredient_blocks[i] == "Ingredient:" and i + 1 < len(raw_ingredient_blocks):
            ingredient_contents.append(raw_ingredient_blocks[i+1].strip())


    modified_ingredient_section_parts = []

    modified_ingredient_section_parts.append(f"--- Ingredient Information ---\n    Total number of ingredients: {total_ingredients}\n")

    for idx, content_block in enumerate(ingredient_contents):
        concentration_risk = ""
        current_total_for_ratio = total_ingredients if total_ingredients > 0 else 1

        pos_ratio = idx / current_total_for_ratio

        if pos_ratio < 0.4:
            concentration_risk = "High"
        elif pos_ratio < 0.7:
            concentration_risk = "Moderate"
        else:
            concentration_risk = "Low"

        if "No ingredients found in the input" in content_block:
            modified_ingredient_section_parts.append(f"Ingredient: {content_block}\n")
        else:
            lines = content_block.split('\n')
            ingredient_name_line = lines[0].strip()

            new_block = [
                f"Ingredient: {ingredient_name_line}",
                f"    Concentration Risk: {concentration_risk}"
            ]
            for i in range(1, len(lines)):
                line = lines[i].strip()
                if line:
                    new_block.append(f"    {line}")

            modified_ingredient_section_parts.append("\n".join(new_block) + "\n\n")


    new_ingredient_section = "".join(modified_ingredient_section_parts).strip()
    new_ingredient_section += "\n\n--- End Ingredient Information ---\n"

    before_info = user_content[:ingredient_info_start]
    after_info = user_content[ingredient_info_end + len("--- End Ingredient Information ---"):].strip()

    return f"{before_info}{new_ingredient_section}\n\n{after_info}"


# --- FastAPI Endpoint ---
@app.post("/extract_ingredients", dependencies=[Depends(current_user)])
async def extract_ingredients_endpoint(request: TextExtractionRequest):
    """
    Endpoint that processes text and returns matched ingredients
    with their details (name, effects, verdict) and then passes
    this information to the LLM for a PCOS-focused verdict.
    """
    raw_text = request.text
    print(f"\n{'='*30} New Request {'='*30}")
    print(f"Input Text: {raw_text[:100]}...")

    # Step 1: Call Ollama LLM for initial extraction
    extracted_ingredients = await call_llm_for_ingredient_extraction(raw_text)

    if not extracted_ingredients:
        print("\n❌ No ingredients extracted by LLM")
        raise HTTPException(status_code=400, detail="No ingredients could be extracted from the provided text.")

    # We will now store full dictionaries for processed ingredients
    processed_ingredient_details = []
    # New list for the desired output format for the UI
    ingredients_summary_for_ui = []

    if driver is None:
        print("\n❌ Neo4j driver not initialized")
        raise HTTPException(status_code=500, detail="Database connection not established.")

    try:
        # Step 2: Query Neo4j for each ingredient and get precise classification
        with driver.session() as session:
            for ingredient_name in extracted_ingredients:
                print(f"\nProcessing ingredient: '{ingredient_name}'")

                # find_ingredient_in_neo4j now returns a dict or None, including 'classification' (raw string or None)
                matched_details = session.execute_read(find_ingredient_in_neo4j, ingredient_name)

                if matched_details:
                    # Add LLM's original extracted name for context
                    matched_details["original_extracted_name"] = ingredient_name
                    
                    # --- NEW: Get precise classification using a dedicated LLM call ---
                    raw_classification_from_db = matched_details.get('classification')
                    llm_determined_classification = await get_precise_classification_from_llm(raw_classification_from_db)
                    
                    # Store this precise classification back into matched_details for consistency
                    # And use it for UI summary
                    matched_details['classification_precise'] = llm_determined_classification
                    # --- END NEW ---

                    processed_ingredient_details.append(matched_details)
                    
                    match_type = "exact match" if matched_details.get("is_exact_match") else "similar match"
                    # Use the LLM-determined precise classification for the UI summary
                    ingredients_summary_for_ui.append([ingredient_name, llm_determined_classification, match_type])

                else:
                    # If not found, add an entry indicating it was not found
                    processed_ingredient_details.append({
                        "original_extracted_name": ingredient_name,
                        "name": f"'{ingredient_name}'",
                        "effects": "Not found in database",
                        "verdict": "Not found in database",
                        "classification": "unknown: Not found in database", # Raw string for main LLM if not found
                        "classification_precise": "unknown", # Precise classification for UI
                        "is_exact_match": False
                    })
                    # Add to summary list even if not found in DB
                    ingredients_summary_for_ui.append([ingredient_name, "unknown", "not found"])

    except Exception as e:
        print(f"\n❌ Database error: {e}")
        raise HTTPException(status_code=500, detail=f"Database error: {e}")

    print(f"\n📋 Final Results:")
    for i, item in enumerate(processed_ingredient_details, 1):
        status_text = "Exact Match" if item.get("is_exact_match") else \
                      ("Closest Match" if item.get("name") and item.get("name") != item.get("original_extracted_name") else "Not Found")

        print(f"{i}. Original: '{item['original_extracted_name']}'")
        print(f"    Matched DB Name: {item.get('name', 'N/A')}")
        print(f"    Effects: {item.get('effects', 'N/A')}")
        print(f"    Verdict: {item.get('verdict', 'N/A')}")
        print(f"    Classification (raw from DB): {item.get('classification', 'N/A')}") # Still log raw for debug
        print(f"    Classification (LLM Precise): {item.get('classification_precise', 'N/A')}") # New log for precise class.
        print(f"    Status: {status_text}")
    print(f"{'='*70}\n")

    # Step 3: Format the Neo4j data for the LLM
    llm_input_string = "Ingredient analysis for PCOS:\n\n"
    llm_input_string += "--- Ingredient Information ---\n"
    llm_input_string += f"    Total number of ingredients: {len(processed_ingredient_details)}\n\n"

    for ingredient_data in processed_ingredient_details:
        # Use original_extracted_name for LLM prompt's ingredient name
        llm_input_string += f"Ingredient: {ingredient_data['original_extracted_name']}\n"
        llm_input_string += f"    Effect: {ingredient_data.get('effects', 'N/A')}\n"
        llm_input_string += f"    PCOS Relevance: {ingredient_data.get('verdict', 'N/A')}\n"  # Using verdict as PCOS Relevance
        # Use the LLM-determined precise classification (single word) for the main LLM
        llm_input_string += f"    Classification: {ingredient_data.get('classification_precise', 'unknown')}\n\n"
    llm_input_string += "--- End Ingredient Information ---\n"


    # Step 4: Inject concentration risk into the formatted string
    llm_input_with_concentration = inject_concentration_risk(llm_input_string)
    print("\n--- LLM Input with Concentration Risk ---")
    print(llm_input_with_concentration)
    print("-----------------------------------------\n")


    # Step 5: Call the Generative LLM
    try:
        llm_response_content = generate_model_content(llm_input_with_concentration)
        print(f"\n--- LLM Final Response ---")
        print(llm_response_content)
        print(f"---------------------------\n")
    except Exception as e:
        print(f"\n❌ Error calling Generative LLM: {e}")
        raise HTTPException(status_code=500, detail=f"Error generating PCOS verdict: {e}")

    # Step 6: Return the LLM's response to the UI
    return {
        "pcos_verdict_and_explanation": llm_response_content,
        "extracted_ingredient_details": processed_ingredient_details,
        "total_ingredients": len(extracted_ingredients),
        "ingredients_summary": ingredients_summary_for_ui  # Uses LLM-determined precise classification
    }
