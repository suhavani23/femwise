<div align="center">

<img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/brand/illustration.png" alt="FemWise" width="160" />

# FemWise

### Your intelligent PCOS companion for Android

**Track smarter. Eat better. Breathe easier.**

[![Website](https://img.shields.io/badge/website-femwise--ai.vercel.app-e98aa6?style=for-the-badge&logo=vercel&logoColor=white)](https://femwise-ai.vercel.app)
[![App code](https://img.shields.io/badge/app%20code-GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/suhavani23/femwise)
[![Platform](https://img.shields.io/badge/platform-Android%206.0%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#-download)
[![Built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](#-tech-stack)
[![Team](https://img.shields.io/badge/made%20by-Team%20Aether-3d2e52?style=for-the-badge)](#-team)

[**🌐 Visit the website**](https://femwise-ai.vercel.app) · [**📲 Download the APK**](https://femwise-ai.vercel.app/#download) · [**💻 App source code**](https://github.com/suhavani23/femwise) · [**⚙️ How it works**](#️-how-it-works)

</div>

---

## 💭 The problem

Polycystic Ovary Syndrome affects roughly **1 in 10 women**. Managing it means a hundred small decisions every day:

- 📅 *When is my next period?* Irregular cycles make ordinary trackers useless.
- 🍽️ *Is this safe to eat?* Food labels are confusing and generic nutrition apps don't know what matters for PCOS.
- 🧘‍♀️ *How do I calm down tonight?* Self-care advice is one-size-fits-all.

Most women end up juggling three apps and still guessing.

## ✨ The solution

**FemWise** brings cycle tracking, AI food analysis and guided self-care into **one calm, personalised app**, so every decision gets easier.

<div align="center">
<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/6.jpg" width="180" alt="Cycle calendar" /><br /><b>Cycle calendar</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/f2.jpg" width="180" alt="Ingredient verdict" /><br /><b>Food verdict</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/14.jpg" width="180" alt="Guided routines" /><br /><b>Guided routines</b></td>
  </tr>
</table>
</div>

## 🌟 What FemWise does

| | Feature | What you get |
|:-:|---|---|
| 📅 | **Cycle tracking & prediction** | A visual calendar marks your current period, predicted next period, ovulation day and fertile window. Log flow, mood and symptoms daily and watch the outlook update. |
| 🔍 | **Packaged-food scanner** | Point the camera at an ingredient label. FemWise reads it, checks every ingredient against a PCOS knowledge graph and gives a clear verdict with healthier swaps. |
| 🍛 | **Cooked-meal analysis** | Snap a home-cooked dish, type its name, and get an ingredient breakdown rated for PCOS suitability. |
| 🧘‍♀️ | **Guided self-care** | Choose stress, anxiety or insomnia and follow yoga poses and breathing exercises built for that concern. |
| 📷 | **Real-time pose matching** | Your camera compares your posture to the reference pose and tells you instantly when your form is right. Runs fully on your phone. |
| 🔒 | **Private by design** | Argon2 password hashing, short-lived sessions, and no video or database credentials ever leave the device. |

## ⚙️ How it works

```mermaid
flowchart LR
    subgraph Phone["📱 On your phone"]
        App["FemWise app<br/>(Flutter)"]
        MLKit["ML Kit<br/>label reading"]
        MoveNet["MoveNet (TFLite)<br/>pose matching"]
    end

    subgraph Services["☁️ FemWise services (FastAPI)"]
        Account["Account API"]
        Label["Label analysis API"]
        Meal["Meal analysis API"]
    end

    subgraph Data["🧠 Data & AI"]
        Mongo[("MongoDB<br/>accounts & logs")]
        Neo4j[("Neo4j<br/>ingredient graph")]
        Chroma[("ChromaDB<br/>dish lookup")]
        LLM["Gemini + Ollama<br/>extraction & verdicts"]
    end

    App --> MLKit
    App --> MoveNet
    App --> Account --> Mongo
    App --> Label --> LLM --> Neo4j
    App --> Meal --> Chroma --> Neo4j
```

<details>
<summary><b>🔎 Food analysis, step by step</b></summary>
<br />

1. **Capture.** The user photographs a label or a cooked dish.
2. **Read.** Google ML Kit extracts the label text on-device.
3. **Extract.** An LLM (Ollama) turns the raw text into a clean ingredient list.
4. **Look up.** Each ingredient is matched in a **Neo4j knowledge graph** holding its effect on PCOS, a verdict and alternatives. Cooked dishes are first mapped to their typical ingredients through **ChromaDB**.
5. **Explain.** Gemini writes a plain-language summary with healthier swaps.
6. **Show.** The app displays an overall verdict and an ingredient breakdown chart.

</details>

<details>
<summary><b>🧘‍♀️ Pose matching, step by step</b></summary>
<br />

1. The routine shows a reference pose and its instructions.
2. A **MoveNet Lightning** model (TensorFlow Lite) estimates the user's body keypoints from the live camera feed.
3. The app compares those keypoints to the reference and shows **Good posture** or guidance to adjust.
4. Everything runs on the phone. No video is uploaded anywhere.

</details>

<details>
<summary><b>🔐 Accounts and data</b></summary>
<br />

- Sign-up and sign-in go through the FastAPI **Account API**.
- Passwords are hashed with **Argon2**; sessions use random bearer tokens that expire after 7 days and are revoked on logout.
- Profiles and daily logs live in **MongoDB**. A day's log and the cycle status are saved in one atomic update.
- The app never holds a database connection string.

</details>

## 📸 Screens

<div align="center">
<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/4.jpg" width="150" alt="Onboarding" /><br />Onboarding</td>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/6.jpg" width="150" alt="Cycle calendar" /><br />Calendar</td>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/9.jpg" width="150" alt="Daily log" /><br />Daily log</td>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/12.jpg" width="150" alt="Log details" /><br />Log details</td>
  </tr>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/o1.jpg" width="150" alt="Cooked meal scan" /><br />Meal scan</td>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/f1.jpg" width="150" alt="Label scan" /><br />Label scan</td>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/f3.jpg" width="150" alt="Ingredient verdict" /><br />Verdict</td>
    <td align="center"><img src="https://raw.githubusercontent.com/parasmani-dev/Femwise/main/assets/screens/13.jpg" width="150" alt="Self-care hub" /><br />Self-care</td>
  </tr>
</table>
</div>

## 📲 Download

> **Free, direct APK. Android 6.0 or newer.**

1. Open the download page: **[femwise-ai.vercel.app/#download](https://femwise-ai.vercel.app/#download)**
2. Tap **Download APK** and open the file. If Android asks, allow installs from this source (normal for apps outside Google Play).
3. Sign up, answer a few questions about your cycle, and you're in.

## 🛠️ Tech stack

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat-square&logo=dart&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=flat-square&logo=fastapi&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-47A248?style=flat-square&logo=mongodb&logoColor=white)
![Neo4j](https://img.shields.io/badge/Neo4j-4581C3?style=flat-square&logo=neo4j&logoColor=white)
![ChromaDB](https://img.shields.io/badge/ChromaDB-FF6F3C?style=flat-square)
![Google ML Kit](https://img.shields.io/badge/Google%20ML%20Kit-4285F4?style=flat-square&logo=google&logoColor=white)
![TensorFlow Lite](https://img.shields.io/badge/TensorFlow%20Lite-FF6F00?style=flat-square&logo=tensorflow&logoColor=white)
![Gemini](https://img.shields.io/badge/Gemini-8E75B2?style=flat-square&logo=googlegemini&logoColor=white)
![Ollama](https://img.shields.io/badge/Ollama-000000?style=flat-square&logo=ollama&logoColor=white)
![Vercel](https://img.shields.io/badge/Vercel-000000?style=flat-square&logo=vercel&logoColor=white)

</div>

| Layer | Technology | Role |
|---|---|---|
| App | Flutter, Dart | Cross-platform UI, calendar, logging, camera flows |
| On-device ML | Google ML Kit, TensorFlow Lite (MoveNet) | Label text recognition, real-time pose estimation |
| Backend | FastAPI (Python) | Account, label-analysis and meal-analysis services |
| Storage | MongoDB | Accounts, profiles, daily logs |
| Knowledge | Neo4j | Ingredient → effect → verdict → alternative graph |
| Retrieval | ChromaDB | Dish name → typical ingredients |
| Inference | OpenAI | Ingredient extraction and plain-language verdicts |
| Website | HTML, CSS, JavaScript on Vercel | Landing page and APK download |

## 🧭 Project links

| | Link |
|---|---|
| 🌐 Website | [femwise-ai.vercel.app](https://femwise-ai.vercel.app) |
| 💻 App source (Flutter + FastAPI) | [github.com/suhavani23/femwise](https://github.com/suhavani23/femwise) |
| 🖥️ Website source | [github.com/parasmani-dev/Femwise](https://github.com/parasmani-dev/Femwise) |

<details>
<summary><b>🚀 Run the app locally</b></summary>
<br />

**Backend (account API)**

```bash
cd backend
python -m venv .venv
.venv/Scripts/activate        # Windows  |  source .venv/bin/activate on macOS/Linux
pip install -r requirements-accounts.txt
cp .env.example .env          # set MONGODB_URI
uvicorn account_api:app --env-file .env --host 0.0.0.0 --port 8002 --reload
```

**App**

```bash
flutter pub get
flutter run --dart-define=ACCOUNT_API_URL=http://10.0.2.2:8002
```

`10.0.2.2` reaches your computer from the Android emulator. On a real phone, use your PC's LAN IP. The food-analysis services need Neo4j, ChromaDB and model keys configured separately.

</details>

## 🗺️ Roadmap

- [ ] Smarter cycle predictions that learn from logged history
- [ ] Barcode lookup for packaged foods
- [ ] More self-care programs and longer routines
- [ ] Google Play release

## 👥 Team

Built with care by **Team Aether**: designers and engineers who believe PCOS care should feel intelligent and kind.

---

<div align="center">

*FemWise is a wellness companion, not a medical device. Always consult a healthcare professional.*

**If FemWise resonates with you, a ⭐ on this repo means a lot.**

</div>
