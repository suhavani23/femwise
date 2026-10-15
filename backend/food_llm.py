"""Use OpenAI (or Google Gen AI) with an environment-selected model."""
import os
from fastapi import HTTPException


def generate_text(prompt, temperature=0.7, max_output_tokens=2048):
    openai_key = os.environ.get("OPENAI_API_KEY")
    gemini_key = os.environ.get("GEMINI_API_KEY")

    if openai_key:
        try:
            from openai import OpenAI
            client = OpenAI(api_key=openai_key)
            response = client.chat.completions.create(
                model=os.environ.get("OPENAI_MODEL", "gpt-4o-mini"),
                messages=[{"role": "user", "content": prompt}],
                temperature=temperature,
                max_tokens=max_output_tokens,
            )
            content = response.choices[0].message.content
            if not content:
                raise ValueError("Empty analysis from OpenAI")
            return content
        except Exception as error:
            raise HTTPException(503, "Food analysis is temporarily unavailable. Please try again later.") from error

    if gemini_key:
        try:
            from google import genai
            from google.genai import types
            with genai.Client(api_key=gemini_key) as client:
                response = client.models.generate_content(
                    model=os.environ.get("GEMINI_MODEL", "gemini-flash-latest"),
                    contents=prompt,
                    config=types.GenerateContentConfig(temperature=temperature,
                        max_output_tokens=max_output_tokens),
                )
            if not response.text:
                raise ValueError("Empty analysis from Gemini")
            return response.text
        except Exception as error:
            raise HTTPException(503, "Food analysis is temporarily unavailable. Please try again later.") from error

    raise HTTPException(503, "Food analysis has not been configured. Set OPENAI_API_KEY or GEMINI_API_KEY.")

