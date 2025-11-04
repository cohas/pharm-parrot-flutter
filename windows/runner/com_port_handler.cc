#include "com_port_handler.h"
#include <sstream>

ComPortHandler::ComPortHandler()
    : port_handle_(INVALID_HANDLE_VALUE), should_stop_(false) {}

ComPortHandler::~ComPortHandler() { CloseComPort(); }

bool ComPortHandler::OpenComPort(int port_number, DWORD baud_rate) {
  if (IsOpen()) {
    CloseComPort();
  }

  // Create COM port name (COM1, COM2, ...)
  std::string port_name = "\\\\.\\COM" + std::to_string(port_number);

  // Open COM port
  port_handle_ = CreateFileA(
      port_name.c_str(),
      GENERIC_READ | GENERIC_WRITE,
      0,
      NULL,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      NULL);

  if (port_handle_ == INVALID_HANDLE_VALUE) {
    return false;
  }

  // Set buffer size
  SetupComm(port_handle_, 4096, 4096);

  // Clear existing buffers
  PurgeComm(port_handle_, PURGE_RXCLEAR | PURGE_TXCLEAR);

  // DCB (Device Control Block) setup
  DCB dcb = {};
  dcb.DCBlength = sizeof(DCB);

  if (!GetCommState(port_handle_, &dcb)) {
    CloseHandle(port_handle_);
    port_handle_ = INVALID_HANDLE_VALUE;
    return false;
  }

  // Configure communication parameters
  dcb.BaudRate = baud_rate;
  dcb.ByteSize = 8;           // Data bits: 8
  dcb.StopBits = ONESTOPBIT;  // Stop bits: 1
  dcb.Parity = NOPARITY;      // Parity: None
  dcb.fDsrSensitivity = FALSE;
  dcb.fOutxCtsFlow = FALSE;
  dcb.fOutxDsrFlow = FALSE;
  dcb.fDtrControl = DTR_CONTROL_ENABLE;
  dcb.fRtsControl = RTS_CONTROL_ENABLE;

  if (!SetCommState(port_handle_, &dcb)) {
    CloseHandle(port_handle_);
    port_handle_ = INVALID_HANDLE_VALUE;
    return false;
  }

  // Set timeout
  COMMTIMEOUTS timeouts = {};
  timeouts.ReadIntervalTimeout = 50;
  timeouts.ReadTotalTimeoutConstant = 50;
  timeouts.ReadTotalTimeoutMultiplier = 0;
  timeouts.WriteTotalTimeoutConstant = 50;
  timeouts.WriteTotalTimeoutMultiplier = 0;

  if (!SetCommTimeouts(port_handle_, &timeouts)) {
    CloseHandle(port_handle_);
    port_handle_ = INVALID_HANDLE_VALUE;
    return false;
  }

  // Start read thread
  should_stop_ = false;
  read_thread_ = std::thread(&ComPortHandler::ReadThreadProc, this);

  return true;
}

void ComPortHandler::CloseComPort() {
  if (IsOpen()) {
    should_stop_ = true;

    if (read_thread_.joinable()) {
      read_thread_.join();
    }

    CloseHandle(port_handle_);
    port_handle_ = INVALID_HANDLE_VALUE;
  }
}

bool ComPortHandler::WriteData(const std::string& data) {
  if (!IsOpen()) {
    return false;
  }

  DWORD bytes_written = 0;
  if (!WriteFile(port_handle_, data.c_str(), static_cast<DWORD>(data.length()), &bytes_written,
                 NULL)) {
    return false;
  }

  return bytes_written == static_cast<DWORD>(data.length());
}

std::string ComPortHandler::ReadData() {
  std::lock_guard<std::mutex> lock(queue_mutex_);

  if (data_queue_.empty()) {
    return "";
  }

  std::string data = data_queue_.front();
  data_queue_.pop();
  return data;
}

std::string ComPortHandler::GetLineData() {
  std::lock_guard<std::mutex> lock(queue_mutex_);

  if (data_queue_.empty()) {
    return "";
  }

  std::string data = data_queue_.front();
  data_queue_.pop();
  return data;
}

void ComPortHandler::ReadThreadProc() {
  unsigned char buffer[1024];
  DWORD bytes_read = 0;

  while (!should_stop_) {
    // Read data from port
    if (ReadFile(port_handle_, buffer, sizeof(buffer), &bytes_read, NULL)) {
      if (bytes_read > 0) {
        std::string data(reinterpret_cast<char*>(buffer), bytes_read);

        // Process line by line
        for (char c : data) {
          partial_line_ += c;

          // Detect newline character
          if (c == '\n' || c == '\r') {
            if (!partial_line_.empty()) {
              // Remove newline characters
              std::string line = partial_line_;
              line.erase(
                  std::remove_if(line.begin(), line.end(),
                                 [](char ch) { return ch == '\r' || ch == '\n'; }),
                  line.end());

              if (!line.empty()) {
                std::lock_guard<std::mutex> lock(queue_mutex_);
                data_queue_.push(line);
              }
            }
            partial_line_.clear();
          }
        }
      }
    } else {
      // Read failed
      Sleep(10);
    }
  }
}
