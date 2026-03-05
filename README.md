<img width="1920" height="1080" alt="Set an aralm at 4PM (3)" src="https://github.com/user-attachments/assets/fee5fabb-f35d-4255-80db-fa923409815b" />

# 🎯 NEXUS - AI Vision Chat App

> **Intelligent conversational AI with real-time image analysis, web search integration, and voice interaction**

![Flutter](https://img.shields.io/badge/Flutter-3.41.2-blue?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.11.0-blue?logo=dart)
![License](https://img.shields.io/badge/License-MIT-green)
![Status](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)

---

## 📱 Overview

**NEXUS** is a cutting-edge Flutter application that combines intelligent AI with real-time capabilities:

- 🤖 **Gemini AI** - Advanced language model with vision capabilities
- 📷 **Real-time Vision Analysis** - Capture and analyze images instantly
- 🌐 **Web Search Integration** - Fetch live information with Serper API
- 🎤 **Voice Interaction** - Speech recognition and text-to-speech
- 💾 **Smart Caching** - Offline search results and conversation history
- 🔄 **Follow-up Conversations** - Reuse images for contextual queries



<p align="center">
  <img src="https://github.com/user-attachments/assets/cd7e17c7-4969-4dfe-8f77-b073e73a5572" width="310"/>
  <img src="https://github.com/user-attachments/assets/8d576f06-c5a5-4084-a5ef-509411559a5b" width="310"/>
  <!-- <img src="https://github.com/user-attachments/assets/2cb02084-de9b-47d2-8393-005260190726" width="280"/> -->
</p>

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| 👁️ **Vision Chat** | Ask questions about images in real-time |
| 🌐 **Web Search** | Integrated search with live results |
| 🎤 **Voice Input** | Speak your queries naturally |
| 🔊 **Audio Response** | Hear AI responses via TTS |
| 📸 **Image Reuse** | Use last captured image for follow-ups |
| 💾 **Search Caching** | Offline access to previous searches |
| 💬 **Message History** | Persistent conversation storage |
| 🔗 **Function Calling** | Gemini tools integration |
| ⏱️ **Timeout Management** | 5-second tool execution limits |
| 🎯 **Context Awareness** | ChatSession support for continuous conversations |

---

## 🛠️ Tech Stack

### Frontend
- **Framework**: Flutter 3.41.2
- **State Management**: BLoC (Business Logic Component)
- **UI**: Material Design 3
- **Camera**: CameraX integration

### Backend & APIs
- **AI Model**: Google Gemini 2.5 Flash
- **Vision API**: Gemini Vision
- **Search**: Serper API (Google Search)
- **Speech**: Google Cloud Speech-to-Text
- **TTS**: Google Cloud Text-to-Speech

### Database & Storage
- **Local DB**: SQLite (Hive)
- **Cache**: Search results database
- **File Storage**: Image caching

### Architecture
- **Pattern**: Clean Architecture
- **Layers**: Presentation → Domain → Data
- **DI**: GetIt Service Locator
- **Async**: Dart Futures & Streams

---

## 🏗️ Project Architecture

```
lib/
├── main.dart                          # App entry point
├── config/
│   ├── app_constants.dart            # API keys & constants
│   └── di_container.dart             # Dependency injection
├── features/
│   ├── chat/
│   │   ├── presentation/
│   │   │   ├── bloc/                 # BLoC logic
│   │   │   ├── pages/                # UI screens
│   │   │   └── widgets/              # Reusable components
│   │   ├── domain/
│   │   │   ├── entities/             # Business models
│   │   │   ├── repositories/         # Abstract repos
│   │   │   └── usecases/             # Business logic
│   │   └── data/
│   │       ├── datasources/          # Remote & local data
│   │       ├── models/               # Data models
│   │       └── repositories/         # Implementations
│   ├── camera/
│   ├── speech/
│   └── search/
├── core/
│   ├── error/                        # Error handling
│   ├── network/                      # HTTP client
│   ├── usecase/                      # Base usecase
│   └── utils/                        # Utilities
└── assets/                           # Images, fonts, etc.
```

---

## 🎯 How It Works

### Vision Search Flow

```
User Input (Voice/Text)
        ↓
Camera Capture (if needed)
        ↓
Gemini Vision API
        ↓
Detect Function Calls (search_web)
        ↓
YES → Execute Web Search (Serper API)
        ↓
Cache Results (SQLite)
        ↓
Send Results Back to Gemini
        ↓
Generate Final Response
        ↓
TTS Output
```

### ChatSession Context

```
Message 1: User asks question + Image
        ↓
Gemini Response (with context)
        ↓
Message 2: User follow-up question
        ↓
Gemini Response (remembers image from Message 1)
        ↓
Message 3: Another follow-up
        ↓
Continuous context maintained
```

---

## 📦 Dependencies

```yaml
# State Management
bloc: ^8.1.0
flutter_bloc: ^8.1.0

# Networking
http: ^1.1.0
dio: ^5.3.0

# Local Storage
hive: ^2.2.0
hive_flutter: ^1.1.0
sqflite: ^2.3.0

# AI & APIs
google_generative_ai: ^0.3.0
speech_to_text: ^6.3.0
flutter_tts: ^0.13.0

# Camera
camera: ^0.10.0
image_picker: ^1.0.0

# Utilities
get_it: ^7.5.0
dotenv: ^0.0.1
intl: ^0.19.0
```

---

## 🚀 Quick Start

1. **Clone the repository**
```bash
git clone https://github.com/Istiak-Ahmed78/NEXUS_AI.git
cd NEXUS_AI
```

2. **Install dependencies**
```bash
flutter pub get
```

3. **Configure API Keys**

Create `.env` file:
```env
GEMINI_API_KEY=your_gemini_api_key_here
SERPER_API_KEY=your_serper_api_key_here
```

4. **Run the app**
```bash
flutter run
```

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---
