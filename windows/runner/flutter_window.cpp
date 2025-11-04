#include "flutter_window.h"

#include <optional>
#pragma warning(push)
#pragma warning(disable: 4996)
#include <sapi.h>
#include <sphelper.h>
#pragma warning(pop)

#include "flutter/generated_plugin_registrant.h"
#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {
  // Initialize COM and create TTS voice
  CoInitialize(nullptr);
  CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL, IID_ISpVoice, (void**)&tts_voice_);
  
  // Initialize COM Port handler
  com_port_handler_ = std::make_unique<ComPortHandler>();
}

FlutterWindow::~FlutterWindow() {
  // Release TTS voice
  if (tts_voice_) {
    tts_voice_->Release();
    tts_voice_ = nullptr;
  }
  CoUninitialize();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  
  // Setup TTS platform channel
  SetupTtsChannel();
  
  // Setup Window platform channel
  SetupWindowChannel();
  
  // Setup COM Port platform channel
  SetupComPortChannel();
  
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetupTtsChannel() {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "pharm_parrot/tts",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "speak") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            auto text_it = arguments->find(flutter::EncodableValue("text"));
            if (text_it != arguments->end()) {
              std::string text = std::get<std::string>(text_it->second);
              
              if (tts_voice_) {
                // UTF-8 to Wide String conversion
                int wchars_num = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
                wchar_t* wstr = new wchar_t[wchars_num];
                MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, wstr, wchars_num);
                
                // Use SPF_ASYNC for non-blocking speech
                // The global tts_voice_ persists so audio won't be cut off
                tts_voice_->Speak(wstr, SPF_ASYNC | SPF_PURGEBEFORESPEAK, nullptr);
                
                delete[] wstr;
                result->Success();
              } else {
                result->Error("TTS_ERROR", "TTS voice not initialized");
              }
              
              return;
            }
          }
          result->Error("INVALID_ARGUMENT", "Text argument is required");
        } else if (call.method_name() == "beep") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            auto freq_it = arguments->find(flutter::EncodableValue("frequency"));
            auto dur_it = arguments->find(flutter::EncodableValue("duration"));
            
            if (freq_it != arguments->end() && dur_it != arguments->end()) {
              int frequency = std::get<int>(freq_it->second);
              int duration = std::get<int>(dur_it->second);
              
              // Windows Beep API
              Beep(frequency, duration);
              result->Success();
              return;
            }
          }
          result->Error("INVALID_ARGUMENT", "Frequency and duration required");
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::SetupWindowChannel() {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.example.pharm_parrot_flutter/window",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setWindowGeometry") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            auto left_it = arguments->find(flutter::EncodableValue("left"));
            auto top_it = arguments->find(flutter::EncodableValue("top"));
            auto width_it = arguments->find(flutter::EncodableValue("width"));
            auto height_it = arguments->find(flutter::EncodableValue("height"));
            
            if (left_it != arguments->end() && 
                top_it != arguments->end() && 
                width_it != arguments->end() && 
                height_it != arguments->end()) {
              
              int left = std::get<int>(left_it->second);
              int top = std::get<int>(top_it->second);
              int width = std::get<int>(width_it->second);
              int height = std::get<int>(height_it->second);
              
              HWND hwnd = GetHandle();
              if (hwnd) {
                SetWindowPos(hwnd, nullptr, left, top, width, height, SWP_NOZORDER);
                result->Success();
                return;
              }
            }
          }
          result->Error("INVALID_ARGUMENT", "Window geometry parameters required");
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::SetupComPortChannel() {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.example.pharm_parrot_flutter/comport",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "openComPort") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            auto port_it = arguments->find(flutter::EncodableValue("portNumber"));
            auto baud_it = arguments->find(flutter::EncodableValue("baudRate"));
            
            if (port_it != arguments->end() && baud_it != arguments->end()) {
              int port_number = std::get<int>(port_it->second);
              int baud_rate = std::get<int>(baud_it->second);
              
              bool success = com_port_handler_->OpenComPort(port_number, baud_rate);
              result->Success(success);
              return;
            }
          }
          result->Error("INVALID_ARGUMENT", "Port number and baud rate required");
        } else if (call.method_name() == "closeComPort") {
          com_port_handler_->CloseComPort();
          result->Success();
        } else if (call.method_name() == "readComPort") {
          std::string data = com_port_handler_->GetLineData();
          result->Success(data);
        } else if (call.method_name() == "writeComPort") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            auto data_it = arguments->find(flutter::EncodableValue("data"));
            if (data_it != arguments->end()) {
              std::string data = std::get<std::string>(data_it->second);
              bool success = com_port_handler_->WriteData(data);
              result->Success(success);
              return;
            }
          }
          result->Error("INVALID_ARGUMENT", "Data required");
        } else {
          result->NotImplemented();
        }
      });
}
