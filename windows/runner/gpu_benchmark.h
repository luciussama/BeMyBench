#ifndef RUNNER_GPU_BENCHMARK_H_
#define RUNNER_GPU_BENCHMARK_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <map>

class GpuBenchmarkWin {
 public:
  static void Register(flutter::BinaryMessenger* messenger);

  static std::map<flutter::EncodableValue, flutter::EncodableValue> GetInfo();
  static std::map<flutter::EncodableValue, flutter::EncodableValue> RunCompute(int duration_ms);
  static std::map<flutter::EncodableValue, flutter::EncodableValue> RunRender(int duration_ms);
  static bool Open3dWindow(const std::string& mode);
  static bool Close3dWindow();
  static bool Is3dWindowOpen();
};

#endif  // RUNNER_GPU_BENCHMARK_H_
