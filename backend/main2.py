from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
import os
import json
import re
import math
from neo4j import GraphDatabase
import google.generativeai as genai
import time # Import the time module for sleeping
import logging
import chromadb # Import chromadb

# --- Initialize FastAPI App ---
app = FastAPI()

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# --- Configuration for ChromaDB and Neo4j ---
CHROMA_DB_PATH = os.environ.get("CHROMA_DB_PATH", "chroma_data")  # Directory holding the ChromaDB data
COLLECTION_NAME = "cooked_dishes" # This is the static collection name, as per your code

# --- Neo4j Connection Details ---
NEO4J_URI = os.environ.get("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USERNAME = os.environ.get("NEO4J_USERNAME", "neo4j")
NEO4J_PASSWORD = os.environ.get("NEO4J_PASSWORD", "")

# Global Neo4j driver
neo4j_driver = None

@app.on_event("startup")
async def startup_db_client():
    """Connect to Neo4j on FastAPI startup."""
    global neo4j_driver
    try:
        neo4j_driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USERNAME, NEO4J_PASSWORD))
        neo4j_driver.verify_connectivity()
        logger.info("Successfully connected to Neo4j.")
    except Exception as e:
        logger.error(f"Failed to connect to Neo4j: {e}")
        # Optionally, raise an exception or exit if DB connection is critical
        raise HTTPException(status_code=500, detail=f"Failed to connect to Neo4j: {e}")

@app.on_event("shutdown")
async def shutdown_db_client():
    """Close Neo4j connection on FastAPI shutdown."""
    global neo4j_driver
    if neo4j_driver:
        neo4j_driver.close()
        logger.info("Neo4j connection closed.")

# --- ChromaDB Client Initialization ---
# This is initialized globally as it's persistent
try:
    chroma_client = chromadb.PersistentClient(path=CHROMA_DB_PATH)
    # Attempt to get the collection to ensure it exists or can be created/accessed
    try:
        _ = chroma_client.get_or_create_collection(name=COLLECTION_NAME)
        logger.info(f"Successfully initialized ChromaDB client and accessed collection: '{COLLECTION_NAME}'")
    except Exception as e:
        logger.error(f"Error accessing ChromaDB collection '{COLLECTION_NAME}': {e}")
        # If collection access fails, subsequent calls will also fail
        raise HTTPException(status_code=500, detail=f"Error accessing ChromaDB collection: {e}")
except ImportError:
    logger.error("ChromaDB not installed. Please install it using 'pip install chromadb'.")
    raise ImportError("ChromaDB not installed. Please install it using 'pip install chromadb'.")
except Exception as e:
    logger.error(f"Failed to initialize ChromaDB client: {e}")
    raise HTTPException(status_code=500, detail=f"Failed to initialize ChromaDB client: {e}")


# --- All your existing functions go here ---

# Function to identify highly contributing ingredients based on quantity
def get_highly_contributing_ingredients_by_quantity(ingredients_detailed: list, dish_name: str) -> list:
    """
    Analyzes the detailed ingredients list to identify "highly contributing" ingredients
    based primarily on their mentioned quantity, and secondarily on their role in the dish.
    Returns a list of contributing ingredient names, sorted by contribution score in descending order.
    """
    ingredient_scores = {}

    # Define unit weights (higher means more contributing)
    unit_weights = {
        "cup": 100,
        "large": 80,
        "medium": 60,
        "small": 40,
        "tbsp": 50,
        "tsp": 20,
        "gram": 1, "g": 1,
        "kg": 1000,
        "ml": 0.1, "liter": 100,
        "piece": 25,
        "inch": 30,
        "pinch":0.05,
    }

    # Regex to find numbers and units, and qualitative terms
    quantity_pattern = re.compile(r'(\d*\.?\d*)\s*(cup|tbsp|tsp|gram|g|kg|ml|liter|inch|piece)s?|\b(large|medium|small)\b', re.IGNORECASE)

    main_component_keywords = []
    dish_name_lower = dish_name.lower()
    # Updated to be more general for "Mutton Chukka"
    if "mutton" in dish_name_lower:
        main_component_keywords.append("mutton")
    if "chukka" in dish_name_lower:
        # For chukka, main components could be the primary protein or the spice mix
        main_component_keywords.extend(["spice", "powder", "meat"])


    for ing in ingredients_detailed:
        item = ing.get('item', '').lower().strip()
        quantity_str = str(ing.get('quantity', '')).lower().strip()

        score = 0
        numerical_value = 1.0

        if any(keyword in item for keyword in main_component_keywords if keyword):
            score += 500

        match = quantity_pattern.search(quantity_str)
        if match:
            num_part_str = match.group(1)
            unit_part = match.group(2)
            qualitative_part = match.group(3)

            if num_part_str:
                try:
                    numerical_value = float(num_part_str)
                except ValueError:
                    numerical_value = 1.0

            if unit_part:
                score += numerical_value * unit_weights.get(unit_part, 0)
            elif qualitative_part:
                score += numerical_value * unit_weights.get(qualitative_part, 0)

        if not match:
            # Enhanced to catch more relevant base ingredients for general dishes
            if "mutton" in item: # Explicitly scoring mutton higher as it's the main component
                score += 300
            elif "onion" in item:
                score += 70
            elif "tomatoes" in item:
                score += 70
            elif "potato" in item:
                score += 80
            elif "ginger" in item or "garlic" in item:
                score += 60
            elif "oil" in item:
                score += 50
            elif "ghee" in item: # Added ghee
                score += 50
            elif "masala" in item or "spice powder" in item: # Catching spice mixes
                score += 90
            elif "curry leaves" in item or "chilli" in item: # Other common aromatics/spices
                score += 40

        if "water" in item or "salt" in item or "garnish" in item or "for serving" in item:
            score = 0

        original_item = ing.get('item', '').strip()
        if original_item not in ingredient_scores or score > ingredient_scores[original_item]:
            ingredient_scores[original_item] = score

    contribution_threshold = 20 # Keep this threshold as it filters out very minor items

    sorted_contributing_ingredients = sorted(
        [ (item, score) for item, score in ingredient_scores.items() if score > contribution_threshold ],
        key=lambda x: x[1],
        reverse=True
    )

    return [item for item, score in sorted_contributing_ingredients]

# Function to fetch ingredient attributes from Neo4j
def get_ingredient_attributes_from_neo4j(ingredient_name: str, session) -> dict:
    """
    Fetches attributes for a given ingredient from the Neo4j knowledge graph.
    Prioritizes looking for core ingredient names over descriptive ones.
    """
    # Helper to execute a query and return data if found
    def _run_query(session, where_clause, params, order_by_clause=""):
        query = f"""
        MATCH (i:Ingredient)
        WHERE {where_clause}
        OPTIONAL MATCH (i)-[:HAS_EFFECT]->(e)
        OPTIONAL MATCH (e)-[:RELATED_TO]->(r)
        OPTIONAL MATCH (i)-[:HAS_PCOS_RELEVANCE]->(pr)
        OPTIONAL MATCH (i)-[:HAS_CLASSIFICATION]->(c)
        OPTIONAL MATCH (i)-[:HAS_VERDICT]->(v)
        OPTIONAL MATCH (s:Source)<-[:SOURCED_FROM]-(i)
        RETURN i.name AS ingredient, e.description AS effect, r.term AS related_to,
                pr.level AS pcos_relevance, c.text AS classification, v.value AS verdict,
                s.url AS source_url
        {order_by_clause}
        LIMIT 1
        """
        result = session.run(query, **params).single()
        return result.data() if result else None

    normalized_ingredient_name = ingredient_name.lower().strip()

    # Define a list of search terms, ordered by priority
    search_terms = []

    # 1. First, try the original normalized name for an exact match (case-insensitive)
    search_terms.append(normalized_ingredient_name)

    # 2. Extract core words from the ingredient name
    cleaned_name = re.sub(
        r'\b(diced|sliced|small|medium|large|florets|dana|half|full|boneless|skinless|fresh|dried|green|red|yellow|white|\d+\.?\d*\s*(cup|tbsp|tsp|gram|g|kg|ml|liter|inch|piece)s?)\b',
        '',
        normalized_ingredient_name
    ).strip()
    
    potential_parts = re.split(r'[\s,-]+', cleaned_name)
    
    # Expanded generic_words_to_exclude for better filtering
    generic_words_to_exclude = {
        "and", "with", "for", "the", "a", "an", "of", "to", "in", "from",
        "dal", "masoor", "ghee", "desi", "powder", "seeds", "cloves", "paste", # Added more common modifiers
        "leaves", "fresh", "dry", "whole", "ground", "chopped", "crushed"
    } 
    
    filtered_parts = [
        p for p in potential_parts 
        if len(p) > 2 and p not in generic_words_to_exclude
    ]
    
    filtered_parts.sort(key=len, reverse=True)
    search_terms.extend(filtered_parts)

    # Remove duplicates while preserving order
    search_terms_unique = []
    seen = set()
    for term in search_terms:
        if term and term not in seen: # Ensure term is not empty before adding
            search_terms_unique.append(term)
            seen.add(term)

    # Now, iterate through the prioritized search terms
    for term_to_search in search_terms_unique:
        # logger.info(f"    Attempting search for core term: '{term_to_search}' (derived from '{ingredient_name}')")

        # First, try an exact match with the derived core term
        where_exact_core = "toLower(i.name) = toLower($name_param)"
        params_exact_core = {"name_param": term_to_search}
        
        attributes = _run_query(session, where_exact_core, params_exact_core)
        # Check if attributes are not all None (excluding 'ingredient' itself)
        if attributes and any(v is not None for k, v in attributes.items() if k != 'ingredient'):
            # logger.info(f"    Found precise match for core term: '{attributes['ingredient']}'")
            return attributes
        
        # If exact core match fails or has no attributes, try CONTAINS with the derived core term
        where_contains_core = "toLower(i.name) CONTAINS toLower($name_param)"
        params_contains_core = {"name_param": term_to_search}
        
        # Add an ORDER BY clause to prefer shorter, more direct names in CONTAINS matches
        order_by_clause = "ORDER BY size(i.name) ASC"
        attributes = _run_query(session, where_contains_core, params_contains_core, order_by_clause)
        # Check if attributes are not all None (excluding 'ingredient' itself)
        if attributes and any(v is not None for k, v in attributes.items() if k != 'ingredient'):
            # logger.info(f"    Found CONTAINS match for core term: '{attributes['ingredient']}'")
            return attributes
        
    return None # No useful match found after all attempts


# --- Generative Model Setup (from your existing LLM script) ---
GEMINI_API_KEYS = [k.strip() for k in os.environ.get("GEMINI_API_KEYS", "").split(",") if k.strip()] or [""]  # Comma-separated keys from the environment

current_key_index = 0
# Initialize current_api_key, will be updated by configure_gemini()
current_api_key = GEMINI_API_KEYS[current_key_index]

# Modified SYSTEM PROMPT (as per your request)
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
7. dont add " * " these and also dont add "-" this before the new point just beginning in a new line is enough
---
## Example Output:

"Verdict: Potentially Harmful\nExplanation: This product contains Refined Sugar in a high concentration, which is directly linked to exacerbating insulin resistance and inflammation, significant concerns for women with PCOS. While Curcumin is also present in a high concentration and offers direct beneficial effects for insulin sensitivity and hormonal balance, and Whole Grains are a good source of fiber for blood sugar regulation at a moderate concentration, the prominent presence of a highly problematic ingredient like Refined Sugar outweighs these benefits. Additionally, Soy, present in a low concentration, has a complex and potentially varied effect on hormonal balance due to phytoestrogens. Given the high concentration of refined sugar, this product is potentially harmful for women with PCOS despite the presence of beneficial ingredients. Avoiding high concentrations of refined sugars is crucial for managing PCOS symptoms."
"""

# --- Rate Limiting Parameters ---
MAX_REQUESTS_PER_MINUTE = 25 
TIME_WINDOW = 60 # seconds

request_timestamps = [] # To store the timestamps of each request

def enforce_rate_limit():
    global request_timestamps
    current_time = time.time()

    # Remove timestamps older than the time window
    request_timestamps = [t for t in request_timestamps if current_time - t < TIME_WINDOW]

    # If we've made too many requests in the current window, wait
    if len(request_timestamps) >= MAX_REQUESTS_PER_MINUTE:
        time_to_wait = TIME_WINDOW - (current_time - request_timestamps[0])
        if time_to_wait > 0:
            logger.warning(f"Rate limit hit. Waiting for {time_to_wait:.2f} seconds...")
            time.sleep(time_to_wait)
            current_time = time.time()
            request_timestamps = [t for t in request_timestamps if current_time - t < TIME_WINDOW]
    
    # Add the current request's timestamp
    request_timestamps.append(time.time())

def configure_gemini():
    """Configures the Gemini API with the current key."""
    global current_api_key, current_key_index
    if current_key_index < len(GEMINI_API_KEYS):
        current_api_key = GEMINI_API_KEYS[current_key_index]
        genai.configure(api_key=current_api_key)
        logger.info(f"Using Gemini API key index: {current_key_index + 1}/{len(GEMINI_API_KEYS)}")
        return True
    else:
        logger.error("No more Gemini API keys available.")
        return False

# Initial Gemini configuration on startup
configure_gemini()

# NEW: LLM Function for Precise Classification (copied from main.py)
async def get_precise_classification_from_llm(raw_classification_text: str | None) -> str:
    """
    Uses a dedicated LLM call to precisely classify an ingredient's category
    (good, bad, moderate, unknown) from a descriptive text or None.
    """
    if raw_classification_text is None or raw_classification_text.strip().lower() == 'unknown':
        return 'unknown' # Handle None or explicit 'unknown' directly

    prompt_content = (
        f"Analyze the following ingredient classification description and determine its primary category "
        f"for PCOS relevance. Respond with ONLY one of these single words: 'good', 'bad', 'moderate', or 'unknown'.\n\n"
        f"Description: \"\"\"{raw_classification_text}\"\"\"\n\n"
        f"Category:"
    )

    try:
        model_classification = genai.GenerativeModel('gemini-1.5-flash') # Use a separate model instance for this specific task
        response = model_classification.generate_content(
            prompt_content,
            generation_config=genai.types.GenerationConfig(
                temperature=0.0, # Keep temperature low for deterministic classification
                max_output_tokens=10, # Expect a short output
            )
        )
        # Clean the response to ensure it's one of the expected categories
        classified_word = response.text.strip().lower()
        if 'good' in classified_word:
            return 'good'
        elif 'bad' in classified_word:
            return 'bad'
        elif 'moderate' in classified_word or 'potentially' in classified_word:
            return 'moderate'
        else:
            return 'unknown'

    except Exception as e:
        logger.error(f"Error during precise classification LLM call: {e}")
        return 'unknown' # Default to unknown on error

def generate_model_content(user_content_str):
    global current_key_index, current_api_key # Keep them as global
    full_prompt = SYSTEM_PROMPT + "\n\n" + user_content_str
    
    # Ensure a model instance is created with the current key
    model = genai.GenerativeModel('gemini-1.5-flash') 

    while True: # Loop to try with different keys
        try:
            enforce_rate_limit() # Apply rate limiting before each request

            response = model.generate_content(
                full_prompt,
                generation_config=genai.types.GenerationConfig(
                    temperature=0.7,
                    max_output_tokens=1024,
                )
            )
            return response.text
        except Exception as e:
            error_message = str(e).lower()
            if "quota" in error_message or "rate limit" in error_message or "resource exhausted" in error_message:
                logger.warning(f"Quota exhausted for key {current_key_index + 1} ({current_api_key[:5]}...): {e}")
                current_key_index += 1
                if not configure_gemini(): # Try to switch to the next key
                    return "Error: All API keys exhausted. Generation stopped."
            else:
                logger.error(f"Error generating content with Gemini: {e}")
                raise HTTPException(status_code=500, detail=f"Error generating content with Gemini: {e}")
    
    return "Error: All API keys exhausted. Generation stopped."


def inject_concentration_risk(user_content):
    """
    Parses the user content, calculates Concentration Risk for each ingredient
    based on its position, and injects this information into the content string.
    """
    ingredient_info_start = user_content.find("--- Ingredient Information ---")
    ingredient_info_end = user_content.find("--- End Ingredient Information ---")

    if ingredient_info_start == -1 or ingredient_info_end == -1:
        return user_content # Return original if markers not found

    # Extract the full ingredient information block
    info_section = user_content[ingredient_info_start : ingredient_info_end]
    
    # Extract Total number of ingredients
    total_ingredients_match = re.search(r"Total number of ingredients:\s*(\d+)", info_section)
    if not total_ingredients_match:
        logger.warning("Could not find 'Total number of ingredients' in prompt. Returning original content.")
        return user_content # Cannot process without total count

    total_ingredients = int(total_ingredients_match.group(1))
    if total_ingredients == 0:
        logger.info("Total ingredients is 0. Concentration risk won't be calculated meaningfully.")
        pass 

    # Split the ingredient info section by "Ingredient:" to get individual blocks
    # We need to handle the first part before the first "Ingredient:" as well
    parts = re.split(r"(Ingredient:)", info_section)
    
    ingredient_contents = []
    # Reconstruct ingredient blocks, ensuring "Ingredient:" is part of the block's start
    # The split creates ['', 'Ingredient:', ' Content of first ingredient', 'Ingredient:', 'Content of second ingredient', ...]
    # So we combine every two elements starting from index 1
    for i in range(1, len(parts), 2):
        if i + 1 < len(parts):
            ingredient_contents.append(parts[i] + parts[i+1].strip()) # "Ingredient:" + content


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
            
        # Ensure we don't add "Concentration Risk" if the block indicates no ingredients were found
        if "No highly contributing ingredients" in content_block:
            modified_ingredient_section_parts.append(content_block + "\n")
        else:
            # Insert Concentration Risk after the Ingredient: line
            lines = content_block.split('\n')
            
            new_block = [lines[0].strip()] # The "Ingredient: Name" line
            new_block.append(f"    Concentration Risk: {concentration_risk}")
            
            for i in range(1, len(lines)): # Append the rest of the lines
                line = lines[i].strip()
                if line:
                    new_block.append(f"    {line}")

            modified_ingredient_section_parts.append("\n".join(new_block) + "\n\n")


    new_ingredient_section = "".join(modified_ingredient_section_parts).strip()
    new_ingredient_section += "\n\n--- End Ingredient Information ---\n"

    # Reconstruct the full user content with the modified section
    before_info = user_content[:ingredient_info_start]
    after_info = user_content[ingredient_info_end + len("--- End Ingredient Information ---"):].strip()
    
    return f"{before_info}{new_ingredient_section}\n\n{after_info}"


async def get_dish_ingredients_and_attributes(dish_name_to_fetch: str) -> dict:
    """
    Fetches detailed ingredients for a given dish from ChromaDB based on embedding similarity
    and then retrieves attributes for the top contributing ingredients from Neo4j.
    Returns a dictionary containing the dish name, total ingredients, and a list
    of dictionaries for each top contributing ingredient with its attributes.
    """
    dish_info = {
        "dish_name": dish_name_to_fetch,
        "total_ingredients": 0,
        "ingredients_data": [], # This will store the detailed ingredient attributes with precise classification
        "ingredients_summary": [] # This will store the simplified summary for the UI
    }

    try:
        collection = chroma_client.get_collection(name=COLLECTION_NAME)
        logger.info(f"Searching ChromaDB collection: '{COLLECTION_NAME}' for dish similar to: '{dish_name_to_fetch}'")

        results = collection.query(
            query_texts=[dish_name_to_fetch], # Query based on embedding similarity
            n_results=1, # Get the single most similar result
            include=['documents', 'metadatas', 'distances'] # Include distances to evaluate similarity
        )

        # Define a similarity threshold for L2 distance (smaller is more similar).
        SIMILARITY_THRESHOLD = 0.6 # Adjust this based on experimentation

        if results and results['documents'] and results['documents'][0]:
            # Check the distance of the top result
            closest_distance = results['distances'][0][0]
            logger.info(f"Closest match found for '{dish_name_to_fetch}' with distance: {closest_distance}")

            if closest_distance <= SIMILARITY_THRESHOLD:
                # If within threshold, use this document
                doc = results["documents"][0][0]
                meta = results["metadatas"][0][0]
                
                # Use the actual dish name from metadata, which is the exact name stored in DB
                actual_dish_name_in_db = meta.get('dish_name', dish_name_to_fetch)
                dish_info["dish_name"] = actual_dish_name_in_db 

                # Load 'ingredients' from metadata, which is stored as a JSON string
                ingredients_detailed = json.loads(meta.get('ingredients', '[]'))
                
                # The total ingredients should be the count of the highly contributing ones later
                # For now, we get the total from the source list for initial context, but it will be updated.
                # dish_info["total_ingredients"] = len(ingredients_detailed) 
                logger.info(f"Found {len(ingredients_detailed)} raw ingredients for matched dish: '{actual_dish_name_in_db}'.")

                highly_contributing_list = get_highly_contributing_ingredients_by_quantity(ingredients_detailed, doc)
                
                # Update total_ingredients to be the count of highly contributing ingredients
                dish_info["total_ingredients"] = len(highly_contributing_list)

                if highly_contributing_list:
                    n = len(highly_contributing_list)
                    num_to_select = math.ceil(n / 2) # Select top half
                    top_half_contributing_ingredients = highly_contributing_list[:num_to_select]
                    logger.info(f"Top {num_to_select} highly contributing ingredients: {top_half_contributing_ingredients}")

                    if neo4j_driver: # Ensure driver is initialized from startup event
                        with neo4j_driver.session() as session:
                            for ingredient in top_half_contributing_ingredients:
                                attributes = get_ingredient_attributes_from_neo4j(ingredient, session)
                                if attributes:
                                    # NEW: Get precise classification using the dedicated LLM call
                                    raw_classification_from_db = attributes.get('classification')
                                    llm_determined_classification = await get_precise_classification_from_llm(raw_classification_from_db)
                                    
                                    # Add the precise classification to the attributes dictionary
                                    attributes['classification_precise'] = llm_determined_classification
                                    
                                    dish_info["ingredients_data"].append(attributes)
                                    # Populate ingredients_summary for UI
                                    dish_info["ingredients_summary"].append([
                                        ingredient, 
                                        llm_determined_classification, 
                                        "exact match" if attributes.get("ingredient").lower() == ingredient.lower() else "similar match"
                                    ])
                                else:
                                    # If no attributes found, still add to ingredients_data and summary
                                    dish_info["ingredients_data"].append({
                                        "ingredient": ingredient,
                                        "effect": "N/A", "related_to": "N/A", "pcos_relevance": "N/A",
                                        "classification": "unknown", # Raw classification if not found
                                        "classification_precise": "unknown" # Precise classification if not found
                                    })
                                    dish_info["ingredients_summary"].append([ingredient, "unknown", "not found"])
                    else:
                        logger.warning("Neo4j driver not initialized. Cannot fetch ingredient attributes.")
                else:
                    logger.info("No highly contributing ingredients found.")
            else:
                logger.warning(f"No sufficiently similar dish found for '{dish_name_to_fetch}'. Closest match distance ({closest_distance:.2f}) exceeded threshold ({SIMILARITY_THRESHOLD:.2f}).")
        else:
            logger.warning(f"No documents returned from ChromaDB for '{dish_name_to_fetch}'.")

    except Exception as e:
        logger.error(f"An error occurred during ChromaDB interaction: {e}")
    
    return dish_info


# Define a response model for consistency
class AnalysisResponse(BaseModel):
    pcos_verdict_and_explanation: str
    extracted_ingredient_details: list
    total_ingredients: int
    ingredients_summary: list

# --- FastAPI Endpoint for Food Data Upload and Analysis ---
@app.post("/upload_food_data/", response_model=AnalysisResponse)
async def upload_food_data(
    file: UploadFile = File(...), # Image file (received but not used by the current analysis logic)
    dish_name: str = Form(...) # Dish name from the Flutter app
):
    logger.info(f"Received request for dish: '{dish_name}'")

    try:
        pass
    except Exception as e:
        logger.error(f"Error handling uploaded file: {e}")
        raise HTTPException(status_code=500, detail=f"Could not process uploaded file: {e}")

    # 1. Fetch data from ChromaDB and Neo4j using the provided dish_name
    dish_data = await get_dish_ingredients_and_attributes(dish_name) # Await the async function

    # Check if a dish was found and it has ingredients data
    if not dish_data["ingredients_data"] and dish_data["total_ingredients"] == 0:
        logger.warning(f"Could not retrieve sufficient ingredient data for '{dish_name}'.")
        raise HTTPException(status_code=404, detail=f"No detailed ingredient data found or sufficiently similar dish in database for '{dish_name}'.")

    # 2. Format the fetched data into the user prompt string
    user_prompt_parts = [
        f"Analyze the following food item for women with PCOS:",
        f"Food Item: {dish_data['dish_name']}",
        f"--- Ingredient Information ---",
        f"    Total number of ingredients: {dish_data['total_ingredients']}" # This is now len(highly_contributing_list)
    ]

    if dish_data["ingredients_data"]:
        for ing_attr in dish_data["ingredients_data"]:
            user_prompt_parts.append(f"Ingredient: {ing_attr.get('ingredient', 'N/A')}")
            if ing_attr.get('effect'):
                user_prompt_parts.append(f"    Effect: {ing_attr['effect']}")
            if ing_attr.get('related_to'):
                user_prompt_parts.append(f"    Related To: {ing_attr['related_to']}")
            if ing_attr.get('pcos_relevance'):
                user_prompt_parts.append(f"    PCOS Relevance: {ing_attr['pcos_relevance']}")
            # Use the precise classification from the LLM
            user_prompt_parts.append(f"    Classification: {ing_attr.get('classification_precise', 'unknown')}")
            user_prompt_parts.append("") # Add a blank line for readability between ingredients
    else:
        user_prompt_parts.append("No highly contributing ingredients with detailed attributes found in the knowledge graph for this dish.")
    
    user_prompt_parts.append("--- End Ingredient Information ---")

    combined_user_content = "\n".join(user_prompt_parts)

    # 3. Inject Concentration Risk based on the formatted content
    enriched_user_content = inject_concentration_risk(combined_user_content)

    # 4. Generate content using Gemini
    logger.info(f"Generating PCOS analysis for '{dish_data['dish_name']}' with Gemini...")
    generated_content = generate_model_content(enriched_user_content)

    # 5. Return the analysis result to the Flutter app
    # Step 6: Return the LLM's response to the UI
    return AnalysisResponse(
        pcos_verdict_and_explanation=generated_content,
        extracted_ingredient_details=dish_data["ingredients_data"], # This now contains precise classification
        total_ingredients=dish_data["total_ingredients"], # This is len(highly_contributing_list)
        ingredients_summary=dish_data["ingredients_summary"] # Uses LLM-determined precise classification
    )