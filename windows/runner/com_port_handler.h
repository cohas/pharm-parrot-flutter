#ifndef RUNNER_COM_PORT_HANDLER_H_
#define RUNNER_COM_PORT_HANDLER_H_

#include <windows.h>
#include <string>
#include <queue>
#include <thread>
#include <mutex>

class ComPortHandler {
 public:
  ComPortHandler();
  ~ComPortHandler();

  // Open COM port
  bool OpenComPort(int port_number, DWORD baud_rate = 9600);

  // Close COM port
  void CloseComPort();

  // Read data
  std::string ReadData();

  // Write data
  bool WriteData(const std::string& data);

  // Check if port is open
  bool IsOpen() const { return port_handle_ != INVALID_HANDLE_VALUE; }

  // Get line data from queue
  std::string GetLineData();

 private:
  HANDLE port_handle_;
  std::thread read_thread_;
  bool should_stop_;
  std::queue<std::string> data_queue_;
  std::mutex queue_mutex_;

  // Thread procedure for reading
  void ReadThreadProc();

  // Partial line data waiting for newline
  std::string partial_line_;
};

#endif  // RUNNER_COM_PORT_HANDLER_H_
