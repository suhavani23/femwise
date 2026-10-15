# FemWise: Your Intelligent Women's Health Companion

> Built by **Team Aether** for **Chaos**.

> **Latest APK: guest mode.** The app opens without login/signup. Profiles and daily logs are saved locally on the phone. The MongoDB account API remains available for legacy accounts and optional backend services. See [SETUP_STATUS.md](SETUP_STATUS.md) for the current behavior and APK location.

> Accounts, profiles and daily logs now use MongoDB + FastAPI. See [MongoDB setup](MONGODB_SETUP.md).
> For this prepared checkout, start with [SETUP_STATUS.md](SETUP_STATUS.md): completed work, validation, startup commands and remaining account/device setup.

<details>
<summary><strong>📑 Table of Contents (click to expand)</strong></summary>

- [✨ About FemWise](#-about-femwise-your-journey-empowered-by-ai-)
- [🌟 Key Features](#-key-features)
- [📱 App Screenshots & Demos](#-app-screenshots--demos)
- [⚙️ Backend System Visuals](#️-backend-system-visuals)
- [🏗️ Architecture Overview](#️-architecture-overview)
- [💻 Technology Stack](#-technology-stack)
- [🚀 Setup and Installation](#-setup-and-installation)
- [👥 Team Aether](#-team-aether)
- [🙏 Acknowledgements](#-acknowledgements)

</details>

---
## ✨ About FemWise: Your Journey, Empowered by AI ✨

FemWise is a mobile app revolutionizing PCOS management. We offer **AI-driven tracking**, **personalized self-care**, and **intelligent dietary insights** to empower women in understanding their bodies, managing symptoms, and making informed lifestyle choices. Our mission is to transform the PCOS journey into a structured, supportive, and data-driven experience.

## 🌟 Key Features

### 🗓️ Intelligent Tracking & Prediction

* FemWise includes a visual calendar, daily symptom logging and **formula-based estimates** for period dates and fertility windows.

* Current estimates use the last period date and the cycle length entered during onboarding. Adaptive cycle machine learning is future work.

### 🍏 AI-Powered Food Analysis

* Our **AI-powered food scanner** instantly analyzes packaged ingredients and cooked meals for PCOS suitability.

* It flags potential dietary concerns, recommends healthier alternatives, and uses a **knowledge graph** for smart nutritional insights.

### 🧘‍♀️ Personalized Self-Care & AI Pose Matching

* Access guided yoga and meditation routines designed to relieve specific PCOS symptoms.

* With **real-time AI pose matching**, you receive instant feedback to maintain correct form and maximize health benefits.

## 🏗️ Architecture Overview

<p align="center">
  <img src="images/architecture.png" alt="FemWise Architecture Diagram"/>
  <br>
  <i>A high-level overview of the FemWise application architecture.</i>
</p>

## 📱 App Screenshots & Demos

### Onboarding Experience

<table>
  <tr>
    <td align="center">
      <img src="images/4.jpg" alt="Onboarding Screen 1" width="180"/><br>
      <i>Personalized onboarding to tailor your experience.</i>
    </td>
    <td align="center">
      <img src="images/5.jpg" alt="Onboarding Screen 2" width="180"/><br>
      <i>Setting up your profile for intelligent insights.</i>
    </td>
  </tr>
</table>

---

### Intelligent Tracking in Action

<table>
  <tr>
    <td align="center">
      <img src="images/6.jpg" alt="Cycle Tracking UI" width="180"/><br>
      <i>Intuitive cycle calendar with AI-driven predictions and easy daily logging.</i>
    </td>
    <td align="center">
      <img src="images/7.jpg" alt="Detailed Tracking View" width="180"/><br>
      <i>Dive deeper into your cycle patterns and symptoms.</i>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="images/9.jpg" alt="Symptom Logging" width="180"/><br>
      <i>Comprehensive logging for accurate symptom analysis.</i>
    </td>
    <td align="center">
      <img src="images/12.jpg" alt="Prediction Overview" width="180"/><br>
      <i>AI-powered predictions at a glance.</i>
    </td>
  </tr>
</table>

---

### AI-Powered Food Analysis

#### Cooked Food Analysis

<table>
  <tr>
    <td align="center">
      <img src="images/o1.jpg" alt="Cooked Meal Scan 1" width="180"/><br>
      <i>Analyzing a home-cooked meal for PCOS suitability.</i>
    </td>
    <td align="center">
      <img src="images/o2.jpg" alt="Cooked Meal Scan 2" width="180"/><br>
      <i>Detailed breakdown of nutritional components.</i>
    </td>
    <td align="center">
      <img src="images/o3.jpg" alt="Cooked Meal Scan 3" width="180"/>
    </td>
  </tr>
</table>

---

#### Packed Food Analysis

<table>
  <tr>
    <td align="center">
      <img src="images/f1.jpg" alt="Packed Food Scan 1" width="180"/><br>
      <i>Scanning the label of a packaged food item.</i>
    </td>
    <td align="center">
      <img src="images/f2.jpg" alt="Packed Food Scan 2" width="180"/><br>
      <i>Instant analysis for potential dietary concerns.</i>
    </td>
  </tr>
  <tr>
    <td align="center" colspan="2">
      <img src="images/f3.jpg" alt="Packed Food Scan 3" width="180"/>
    </td>
  </tr>
</table>

---

### Interactive Self-Care with AI Pose Matching

<table>
  <tr>
    <td align="center">
      <img src="images/13.jpg" alt="Self-Care Dashboard" width="180"/><br>
      <i>Your personalized hub for well-being.</i>
    </td>
    <td align="center">
      <img src="images/14.jpg" alt="Yoga Routine Selection" width="180"/><br>
      <i>Choose from a variety of guided yoga routines.</i>
    </td>
  </tr>
  <tr>
    <td align="center" colspan="2">
      <img src="images/18.png" alt="AI Pose Matching in Action" width="180"/><br>
      <i>Real-time feedback for perfect form.</i>
    </td>
  </tr>
</table>

## ⚙️ Backend System Visuals

<p align="center">
  <img src="images/neo4j.jpg" alt="Neo4j Knowledge Graph Example"/>
  <br>
  <i>Neo4j knowledge graph structure for food insights.</i>
</p>

## 💻 Technology Stack

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter Badge"/>
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart Badge"/>
  <img src="https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white" alt="FastAPI Badge"/>
  <img src="https://img.shields.io/badge/MongoDB%20Atlas-47A248?style=for-the-badge&logo=mongodb&logoColor=white" alt="MongoDB Atlas Badge"/>
  <img src="https://img.shields.io/badge/Neo4j-458BCA?style=for-the-badge&logo=neo4j&logoColor=white" alt="Neo4j Badge"/>
  <img src="https://img.shields.io/badge/ChromaDB-6C6C6C?style=for-the-badge&logo=chroma&logoColor=white" alt="ChromaDB Badge"/>
  <img src="https://img.shields.io/badge/Google%20ML%20Kit-4285F4?style=for-the-badge&logo=google&logoColor=white" alt="Google ML Kit Badge"/>
  <img src="https://img.shields.io/badge/Google%20Custom%20Search-4285F4?style=for-the-badge&logo=google&logoColor=white" alt="Google Custom Search Badge"/>
  <img src="https://img.shields.io/badge/ScraperAPI-3D96D2?style=for-the-badge&logo=data-transfer&logoColor=white" alt="ScraperAPI Badge"/>
  <img src="https://img.shields.io/badge/BeautifulSoup-0288D1?style=for-the-badge&logo=python&logoColor=white" alt="BeautifulSoup Badge"/>
  <img src="https://img.shields.io/badge/Hugging%20Face-FFD43B?style=for-the-badge&logo=huggingface&logoColor=black" alt="Hugging Face Badge"/>
  <img src="https://img.shields.io/badge/Gemini%20API-FF6F00?style=for-the-badge&logo=google&logoColor=white" alt="Gemini API Badge"/>
  <img src="https://img.shields.io/badge/Ollama-black?style=for-the-badge&logo=ollama&logoColor=white" alt="Ollama Badge"/>
</p>

## 🚀 Setup and Installation

The current app uses **MongoDB through FastAPI** for accounts, profiles and daily logs.
Firebase is no longer required. Follow [MONGODB_SETUP.md](MONGODB_SETUP.md) for database,
backend, Flutter configuration, testing, and migration instructions.

Start `backend/account_api.py` on port **8002**. The existing food APIs remain separate:
`main.py` on **8000** and `main2.py` on **8001**. Their food datasets and model configuration
must be supplied before food analysis works.

## 👥 Team Aether

FemWise is designed and built by **Team Aether**.

## 🙏 Acknowledgements

* Built for **Chaos**. Thanks to the Chaos organizers for the opportunity to build FemWise!
