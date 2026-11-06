#include "gpu_benchmark.h"

#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <d3dcompiler.h>
#include <dwmapi.h>

#include <flutter/standard_method_codec.h>

#include <chrono>
#include <thread>
#include <atomic>
#include <vector>
#include <algorithm>
#include <cmath>
#include <sstream>
#include <iomanip>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")
#pragma comment(lib, "dwmapi.lib")

namespace {

// Dimensões do benchmark off-screen (1080p padrão)
constexpr int kBenchWidth = 1920;
constexpr int kBenchHeight = 1080;
constexpr uint32_t kComputeIterations = 64;
constexpr uint32_t kSceneInstances = 16384;

// Código HLSL do Compute Shader
const char* kComputeShaderSrc = R"(
cbuffer Params : register(b0) {
    uint iterations;
    uint width;
    uint height;
    uint padding;
};
RWStructuredBuffer<float4> Output : register(u0);

[numthreads(256, 1, 1)]
void CSMain(uint3 id : SV_DispatchThreadID) {
    uint total = width * height;
    if (id.x >= total) return;
    float4 v = float4((float)id.x * 0.000001f, 1.0f, 2.0f, 3.0f);
    float4 acc = float4(0.0f, 0.0f, 0.0f, 0.0f);
    for (uint i = 0; i < iterations; ++i) {
        v = v * 1.0000001f + float4(0.000001f, 0.000001f, 0.000001f, 0.000001f);
        float4 s = sin(v);
        float4 c = cos(v.yzwx);
        v = s * c + sqrt(abs(v));
        acc += v;
    }
    Output[id.x] = acc;
}
)";

// Código HLSL do Vertex Shader
const char* kVertexShaderSrc = R"(
struct VSOut {
    float4 pos : SV_Position;
    float2 uv : TEXCOORD0;
};

VSOut VSMain(uint vid : SV_VertexID) {
    VSOut o;
    o.uv = float2((vid << 1) & 2, vid & 2);
    o.pos = float4(o.uv * 2.0f - 1.0f, 0.0f, 1.0f);
    o.pos.y = -o.pos.y;
    return o;
}
)";

// Código HLSL do Pixel Shader (FurMark Donut Vulcânico em Raymarching com ruído fBm)
const char* kPixelShaderSrc = R"(
cbuffer FrameData : register(b0) {
    float time;
    float width;
    float height;
    float iterations;
};

struct PSIn {
    float4 pos : SV_Position;
    float2 uv : TEXCOORD0;
};

float hash(float2 p) {
    p = frac(p * float2(123.34f, 456.21f));
    p += dot(p, p + 45.32f);
    return frac(p.x * p.y);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = frac(p);
    float a = hash(i);
    float b = hash(i + float2(1.0f, 0.0f));
    float c = hash(i + float2(0.0f, 1.0f));
    float d = hash(i + float2(1.0f, 1.0f));
    float2 u = f * f * (3.0f - 2.0f * f);
    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

float fbm(float2 p) {
    float v = 0.0f;
    float a = 0.5f;
    float2 shift = float2(100.0f, 100.0f);
    for (int i = 0; i < 6; ++i) {
        v += a * noise(p);
        p = p * 2.05f + shift;
        a *= 0.5f;
    }
    return v;
}

float sdTorus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float4 PSMain(PSIn input) : SV_Target {
    float2 uv = (input.pos.xy - float2(width, height) * 0.5f) / height;
    float3 ro = float3(0.0f, 3.2f, -6.0f);
    float3 ta = float3(0.0f, 0.0f, 0.0f);
    float3 ww = normalize(ta - ro);
    float3 uu = normalize(cross(ww, float3(0.0f, 1.0f, 0.0f)));
    float3 vv = normalize(cross(uu, ww));
    float3 rd = normalize(uv.x * uu + uv.y * vv + 1.6f * ww);

    float t = 0.1f;
    float d = 1000.0f;
    float3 p = ro;
    float ang = time * 0.9f;
    float cosA = cos(ang);
    float sinA = sin(ang);

    for (int i = 0; i < 48; ++i) {
        p = ro + rd * t;
        float3 q = p;
        float2 rotXZ = float2(cosA * q.x - sinA * q.z, sinA * q.x + cosA * q.z);
        q.x = rotXZ.x;
        q.z = rotXZ.y;
        float disp = fbm(q.xy * 3.5f + float2(time * 0.4f, 0.0f)) * 0.20f;
        d = sdTorus(q, float2(2.2f, 0.85f)) - disp;
        if (d < 0.001f || t > 25.0f) break;
        t += d * 0.65f;
    }

    float3 col = float3(0.04f, 0.02f, 0.02f);
    if (d < 0.02f) {
        float3 eps = float3(0.002f, 0.0f, 0.0f);
        float3 nor = normalize(float3(
            sdTorus(p + eps.xyz, float2(2.2f, 0.85f)) - sdTorus(p - eps.xyz, float2(2.2f, 0.85f)),
            sdTorus(p + eps.zxy, float2(2.2f, 0.85f)) - sdTorus(p - eps.zxy, float2(2.2f, 0.85f)),
            sdTorus(p + eps.yzx, float2(2.2f, 0.85f)) - sdTorus(p - eps.yzx, float2(2.2f, 0.85f))
        ));
        float dif = clamp(dot(nor, float3(0.57f, 0.70f, -0.42f)), 0.0f, 1.0f);
        float glow = fbm(p.xy * 5.0f + float2(time, time * 0.5f));
        float3 magma = lerp(float3(0.85f, 0.08f, 0.01f), float3(1.0f, 0.55f, 0.05f), glow);
        float3 highlight = float3(1.0f, 0.92f, 0.45f) * pow(dif, 4.0f);
        col = magma * dif + highlight;
    } else {
        float sky = fbm(input.uv * 4.0f + float2(time * 0.1f, 0.0f));
        col += float3(0.18f, 0.04f, 0.01f) * sky;
    }

    float vign = 1.0f - length(input.uv - 0.5f) * 0.7f;
    col *= vign;
    return float4(col, 1.0f);
}
)";

struct ConstantBufferParams {
    uint32_t iterations;
    uint32_t width;
    uint32_t height;
    uint32_t padding;
};

struct ConstantBufferFrame {
    float time;
    float width;
    float height;
    float iterations;
};

// Conversão UTF-16 para UTF-8
std::string WideToUtf8(const std::wstring& wstr) {
    if (wstr.empty()) return std::string();
    int size = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (size <= 0) return std::string();
    std::string str(size - 1, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &str[0], size, nullptr, nullptr);
    return str;
}

// Classe singleton para controle do backend D3D11 e da janela flutuante
class D3D11Context {
 public:
  static D3D11Context& Instance() {
      static D3D11Context instance;
      return instance;
  }

  bool Initialize() {
      if (initialized_) return true;

      D3D_FEATURE_LEVEL featureLevels[] = {
          D3D_FEATURE_LEVEL_11_1,
          D3D_FEATURE_LEVEL_11_0,
      };
      D3D_FEATURE_LEVEL featureLevel;

      HRESULT hr = D3D11CreateDevice(
          nullptr,
          D3D_DRIVER_TYPE_HARDWARE,
          nullptr,
          0,
          featureLevels,
          ARRAYSIZE(featureLevels),
          D3D11_SDK_VERSION,
          &device_,
          &featureLevel,
          &context_);

      if (FAILED(hr)) return false;

      // Obtém adaptador e nome da GPU
      IDXGIDevice* dxgiDevice = nullptr;
      if (SUCCEEDED(device_->QueryInterface(__uuidof(IDXGIDevice), (void**)&dxgiDevice))) {
          IDXGIAdapter* adapter = nullptr;
          if (SUCCEEDED(dxgiDevice->GetAdapter(&adapter))) {
              DXGI_ADAPTER_DESC desc;
              adapter->GetDesc(&desc);
              gpu_name_ = WideToUtf8(desc.Description);
              vram_mb_ = static_cast<int>(desc.DedicatedVideoMemory / (1024 * 1024));
              adapter->Release();
          }
          dxgiDevice->Release();
      }

      CompileShaders();
      initialized_ = true;
      return true;
  }

  std::string GetGpuName() const { return gpu_name_.empty() ? "DirectX 11 GPU" : gpu_name_; }
  int GetVramMb() const { return vram_mb_; }
  ID3D11Device* GetDevice() const { return device_; }
  ID3D11DeviceContext* GetContext() const { return context_; }

  ID3D11ComputeShader* GetComputeShader() const { return compute_shader_; }
  ID3D11VertexShader* GetVertexShader() const { return vertex_shader_; }
  ID3D11PixelShader* GetPixelShader() const { return pixel_shader_; }

 private:
  D3D11Context() = default;
  ~D3D11Context() {
      if (compute_shader_) compute_shader_->Release();
      if (vertex_shader_) vertex_shader_->Release();
      if (pixel_shader_) pixel_shader_->Release();
      if (context_) context_->Release();
      if (device_) device_->Release();
  }

  void CompileShaders() {
      ID3DBlob* csBlob = nullptr;
      ID3DBlob* errorBlob = nullptr;
      if (SUCCEEDED(D3DCompile(kComputeShaderSrc, strlen(kComputeShaderSrc), nullptr, nullptr, nullptr, "CSMain", "cs_5_0", 0, 0, &csBlob, &errorBlob))) {
          device_->CreateComputeShader(csBlob->GetBufferPointer(), csBlob->GetBufferSize(), nullptr, &compute_shader_);
          csBlob->Release();
      }
      if (errorBlob) errorBlob->Release();

      ID3DBlob* vsBlob = nullptr;
      if (SUCCEEDED(D3DCompile(kVertexShaderSrc, strlen(kVertexShaderSrc), nullptr, nullptr, nullptr, "VSMain", "vs_5_0", 0, 0, &vsBlob, &errorBlob))) {
          device_->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), nullptr, &vertex_shader_);
          vsBlob->Release();
      }
      if (errorBlob) errorBlob->Release();

      ID3DBlob* psBlob = nullptr;
      if (SUCCEEDED(D3DCompile(kPixelShaderSrc, strlen(kPixelShaderSrc), nullptr, nullptr, nullptr, "PSMain", "ps_5_0", 0, 0, &psBlob, &errorBlob))) {
          device_->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), nullptr, &pixel_shader_);
          psBlob->Release();
      }
      if (errorBlob) errorBlob->Release();
  }

  bool initialized_ = false;
  ID3D11Device* device_ = nullptr;
  ID3D11DeviceContext* context_ = nullptr;
  ID3D11ComputeShader* compute_shader_ = nullptr;
  ID3D11VertexShader* vertex_shader_ = nullptr;
  ID3D11PixelShader* pixel_shader_ = nullptr;
  std::string gpu_name_;
  int vram_mb_ = 0;
};

// Gerenciador da Janela 3D Nativa com VSync OFF e HUD
class GpuLiveWindowWin {
 public:
  static GpuLiveWindowWin& Instance() {
      static GpuLiveWindowWin instance;
      return instance;
  }

  bool Open(const std::string& mode) {
      if (is_open_.load()) {
          if (hwnd_) {
              ShowWindow(hwnd_, SW_RESTORE);
              SetForegroundWindow(hwnd_);
          }
          return true;
      }

      current_mode_ = mode;
      is_running_.store(true);
      render_thread_ = std::thread(&GpuLiveWindowWin::ThreadProc, this);
      return true;
  }

  bool Close() {
      if (!is_open_.load() && !is_running_.load()) return false;
      is_running_.store(false);
      if (hwnd_) {
          PostMessage(hwnd_, WM_CLOSE, 0, 0);
      }
      if (render_thread_.joinable()) {
          render_thread_.join();
      }
      is_open_.store(false);
      return true;
  }

  bool IsOpen() const {
      return is_open_.load();
  }

 private:
  GpuLiveWindowWin() = default;
  ~GpuLiveWindowWin() { Close(); }

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
      if (msg == WM_DESTROY) {
          GpuLiveWindowWin::Instance().is_running_.store(false);
          return 0;
      }
      return DefWindowProc(hwnd, msg, wParam, lParam);
  }

  void ThreadProc() {
      WNDCLASSEXW wc = {sizeof(WNDCLASSEXW)};
      wc.lpfnWndProc = WndProc;
      wc.hInstance = GetModuleHandle(nullptr);
      wc.lpszClassName = L"BMyBenchGpuStressWindowClass";
      wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
      RegisterClassExW(&wc);

      const int winWidth = 1280;
      const int winHeight = 720;

      RECT rect = {0, 0, winWidth, winHeight};
      AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);

      hwnd_ = CreateWindowExW(
          0,
          wc.lpszClassName,
          L"BMyBench — Estresse de GPU (Direct3D 11)",
          WS_OVERLAPPEDWINDOW,
          CW_USEDEFAULT, CW_USEDEFAULT,
          rect.right - rect.left, rect.bottom - rect.top,
          nullptr, nullptr, GetModuleHandle(nullptr), nullptr);

      if (!hwnd_) {
          is_running_.store(false);
          return;
      }

      // Aplica tema escuro na barra de título do Windows 10/11
      BOOL darkMode = TRUE;
      DwmSetWindowAttribute(hwnd_, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &darkMode, sizeof(darkMode));

      ShowWindow(hwnd_, SW_SHOW);
      UpdateWindow(hwnd_);
      is_open_.store(true);

      D3D11Context& d3d = D3D11Context::Instance();
      if (!d3d.Initialize()) {
          is_running_.store(false);
          is_open_.store(false);
          return;
      }

      IDXGIFactory1* factory = nullptr;
      CreateDXGIFactory1(__uuidof(IDXGIFactory1), (void**)&factory);

      DXGI_SWAP_CHAIN_DESC scDesc = {};
      scDesc.BufferCount = 1;
      scDesc.BufferDesc.Width = winWidth;
      scDesc.BufferDesc.Height = winHeight;
      scDesc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
      scDesc.BufferDesc.RefreshRate.Numerator = 60;
      scDesc.BufferDesc.RefreshRate.Denominator = 1;
      scDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
      scDesc.OutputWindow = hwnd_;
      scDesc.SampleDesc.Count = 1;
      scDesc.SampleDesc.Quality = 0;
      scDesc.Windowed = TRUE;
      scDesc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

      IDXGISwapChain* swapChain = nullptr;
      factory->CreateSwapChain(d3d.GetDevice(), &scDesc, &swapChain);
      factory->Release();

      ID3D11Texture2D* backBuffer = nullptr;
      swapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&backBuffer);
      ID3D11RenderTargetView* rtv = nullptr;
      d3d.GetDevice()->CreateRenderTargetView(backBuffer, nullptr, &rtv);
      backBuffer->Release();

      D3D11_BUFFER_DESC cbDesc = {};
      cbDesc.ByteWidth = sizeof(ConstantBufferFrame);
      cbDesc.Usage = D3D11_USAGE_DYNAMIC;
      cbDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
      cbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
      ID3D11Buffer* constBuffer = nullptr;
      d3d.GetDevice()->CreateBuffer(&cbDesc, nullptr, &constBuffer);

      D3D11_VIEWPORT vp = {0.0f, 0.0f, static_cast<float>(winWidth), static_cast<float>(winHeight), 0.0f, 1.0f};

      LARGE_INTEGER freq, tStart, tLast, tNow;
      QueryPerformanceFrequency(&freq);
      QueryPerformanceCounter(&tStart);
      tLast = tStart;

      int frames = 0;
      double fps = 0.0;
      double frameMs = 0.0;
      int frameIndex = 0;

      HFONT hFont = CreateFontW(15, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
                                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                                CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

      MSG msg = {};
      while (is_running_.load()) {
          while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
              if (msg.message == WM_QUIT) {
                  is_running_.store(false);
                  break;
              }
              TranslateMessage(&msg);
              DispatchMessageW(&msg);
          }
          if (!is_running_.load()) break;

          QueryPerformanceCounter(&tNow);
          double dt = static_cast<double>(tNow.QuadPart - tLast.QuadPart) / freq.QuadPart;
          tLast = tNow;

          frames++;
          if (dt > 0.0) {
              frameMs = dt * 1000.0;
              fps = 0.9 * fps + 0.1 * (1.0 / dt);
          }

          float elapsed = static_cast<float>(tNow.QuadPart - tStart.QuadPart) / freq.QuadPart;

          // Atualiza buffer constante
          D3D11_MAPPED_SUBRESOURCE mapped;
          if (SUCCEEDED(d3d.GetContext()->Map(constBuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
              ConstantBufferFrame* p = static_cast<ConstantBufferFrame*>(mapped.pData);
              p->time = elapsed;
              p->width = static_cast<float>(winWidth);
              p->height = static_cast<float>(winHeight);
              p->iterations = 48.0f;
              d3d.GetContext()->Unmap(constBuffer, 0);
          }

          d3d.GetContext()->RSSetViewports(1, &vp);
          d3d.GetContext()->OMSetRenderTargets(1, &rtv, nullptr);
          d3d.GetContext()->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
          d3d.GetContext()->VSSetShader(d3d.GetVertexShader(), nullptr, 0);
          d3d.GetContext()->PSSetShader(d3d.GetPixelShader(), nullptr, 0);
          d3d.GetContext()->PSSetConstantBuffers(0, 1, &constBuffer);
          d3d.GetContext()->Draw(3, 0);

          // VSync OFF: Present(0, 0)
          swapChain->Present(0, 0);

          // Desenha HUD sobre a janela com GDI
          HDC hdc = GetDC(hwnd_);
          if (hdc) {
              RECT hudRect = {20, 20, 320, 240};
              HBRUSH hBg = CreateSolidBrush(RGB(15, 20, 28));
              FillRect(hdc, &hudRect, hBg);
              DeleteObject(hBg);

              HPEN hBorder = CreatePen(PS_SOLID, 1, RGB(34, 211, 238));
              SelectObject(hdc, hBorder);
              SelectObject(hdc, GetStockObject(NULL_BRUSH));
              RoundRect(hdc, hudRect.left, hudRect.top, hudRect.right, hudRect.bottom, 12, 12);
              DeleteObject(hBorder);

              SelectObject(hdc, hFont);
              SetBkMode(hdc, TRANSPARENT);

              std::wstringstream ss;
              ss << L"GPU: " << std::wstring(d3d.GetGpuName().begin(), d3d.GetGpuName().end()) << L"\n"
                 << L"FPS: " << std::fixed << std::setprecision(1) << fps << L" FPS\n"
                 << L"Frame Time: " << std::fixed << std::setprecision(2) << frameMs << L" ms\n"
                 << L"V-RAM: " << d3d.GetVramMb() << L" MB Dedicada\n"
                 << L"VSync: OFF (Livre / Uncapped)\n"
                 << L"Modo: " << std::wstring(current_mode_.begin(), current_mode_.end()) << L"\n"
                 << L"Status: Torture Test Ativo";

              SetTextColor(hdc, RGB(34, 211, 238));
              RECT textRect = {35, 35, 305, 225};
              DrawTextW(hdc, ss.str().c_str(), -1, &textRect, DT_LEFT | DT_TOP);
              ReleaseDC(hwnd_, hdc);
          }

          frameIndex++;
      }

      DeleteObject(hFont);
      if (constBuffer) constBuffer->Release();
      if (rtv) rtv->Release();
      if (swapChain) swapChain->Release();
      if (hwnd_) {
          DestroyWindow(hwnd_);
          hwnd_ = nullptr;
      }
      is_open_.store(false);
  }

  std::thread render_thread_;
  std::atomic<bool> is_running_{false};
  std::atomic<bool> is_open_{false};
  HWND hwnd_ = nullptr;
  std::string current_mode_ = "stress";
};

}  // namespace

void GpuBenchmarkWin::Register(flutter::BinaryMessenger* messenger) {
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "bemybench/gpu", &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler([](const flutter::MethodCall<flutter::EncodableValue>& call,
                                     std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string& method = call.method_name();

        if (method == "info") {
            result->Success(flutter::EncodableValue(GetInfo()));
        } else if (method == "run") {
            int duration_ms = 1500;
            const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
            if (args) {
                auto it = args->find(flutter::EncodableValue("duration_ms"));
                if (it != args->end()) {
                    if (std::holds_alternative<int32_t>(it->second)) {
                        duration_ms = std::get<int32_t>(it->second);
                    } else if (std::holds_alternative<int64_t>(it->second)) {
                        duration_ms = static_cast<int>(std::get<int64_t>(it->second));
                    }
                }
            }
            std::thread([result_ptr = result.release(), duration_ms]() {
                auto res = RunCompute(duration_ms);
                result_ptr->Success(flutter::EncodableValue(res));
                delete result_ptr;
            }).detach();
        } else if (method == "run_render") {
            int duration_ms = 1500;
            const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
            if (args) {
                auto it = args->find(flutter::EncodableValue("duration_ms"));
                if (it != args->end()) {
                    if (std::holds_alternative<int32_t>(it->second)) {
                        duration_ms = static_cast<int32_t>(std::get<int32_t>(it->second));
                    } else if (std::holds_alternative<int64_t>(it->second)) {
                        duration_ms = static_cast<int>(std::get<int64_t>(it->second));
                    }
                }
            }
            std::thread([result_ptr = result.release(), duration_ms]() {
                auto res = RunRender(duration_ms);
                result_ptr->Success(flutter::EncodableValue(res));
                delete result_ptr;
            }).detach();
        } else if (method == "open_3d_window") {
            std::string mode = "stress";
            const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
            if (args) {
                auto it = args->find(flutter::EncodableValue("mode"));
                if (it != args->end() && std::holds_alternative<std::string>(it->second)) {
                    mode = std::get<std::string>(it->second);
                }
            }
            result->Success(flutter::EncodableValue(Open3dWindow(mode)));
        } else if (method == "close_3d_window") {
            result->Success(flutter::EncodableValue(Close3dWindow()));
        } else if (method == "is_3d_window_open") {
            result->Success(flutter::EncodableValue(Is3dWindowOpen()));
        } else {
            result->NotImplemented();
        }
    });

    // Registra o canal de sensores no Windows
    auto sensors_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "bemybench/sensors", &flutter::StandardMethodCodec::GetInstance());

    sensors_channel->SetMethodCallHandler([](const flutter::MethodCall<flutter::EncodableValue>& call,
                                             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "get_sensors") {
            D3D11Context& d3d = D3D11Context::Instance();
            d3d.Initialize();

            flutter::EncodableMap res;
            res[flutter::EncodableValue("has_fan")] = flutter::EncodableValue(true);
            res[flutter::EncodableValue("fan_status")] = flutter::EncodableValue("Controle automático");
            res[flutter::EncodableValue("thermal_state")] = flutter::EncodableValue("Nominal");
            res[flutter::EncodableValue("model")] = flutter::EncodableValue(d3d.GetGpuName());
            result->Success(flutter::EncodableValue(res));
        } else {
            result->NotImplemented();
        }
    });

    // Mantém canais ativos
    static auto s_channel = std::move(channel);
    static auto s_sensors = std::move(sensors_channel);
}

std::map<flutter::EncodableValue, flutter::EncodableValue> GpuBenchmarkWin::GetInfo() {
    D3D11Context& d3d = D3D11Context::Instance();
    bool ok = d3d.Initialize();

    std::map<flutter::EncodableValue, flutter::EncodableValue> map;
    map[flutter::EncodableValue("available")] = flutter::EncodableValue(ok);
    map[flutter::EncodableValue("render_available")] = flutter::EncodableValue(ok);
    map[flutter::EncodableValue("name")] = flutter::EncodableValue(d3d.GetGpuName());
    map[flutter::EncodableValue("unified_memory")] = flutter::EncodableValue(d3d.GetVramMb() < 512);
    map[flutter::EncodableValue("recommended_working_set_mb")] = flutter::EncodableValue(d3d.GetVramMb());
    map[flutter::EncodableValue("max_threads_per_group")] = flutter::EncodableValue(1024);
    map[flutter::EncodableValue("width")] = flutter::EncodableValue(kBenchWidth);
    map[flutter::EncodableValue("height")] = flutter::EncodableValue(kBenchHeight);
    map[flutter::EncodableValue("iterations")] = flutter::EncodableValue(static_cast<int32_t>(kComputeIterations));
    map[flutter::EncodableValue("render_iterations")] = flutter::EncodableValue(64);
    map[flutter::EncodableValue("scene_instances")] = flutter::EncodableValue(static_cast<int32_t>(kSceneInstances));
    map[flutter::EncodableValue("hdr")] = flutter::EncodableValue(true);
    map[flutter::EncodableValue("msaa_samples")] = flutter::EncodableValue(4);
    map[flutter::EncodableValue("bloom")] = flutter::EncodableValue(true);
    return map;
}

std::map<flutter::EncodableValue, flutter::EncodableValue> GpuBenchmarkWin::RunCompute(int duration_ms) {
    D3D11Context& d3d = D3D11Context::Instance();
    if (!d3d.Initialize() || !d3d.GetComputeShader()) {
        std::map<flutter::EncodableValue, flutter::EncodableValue> err;
        err[flutter::EncodableValue("available")] = flutter::EncodableValue(false);
        return err;
    }

    const uint32_t totalPixels = kBenchWidth * kBenchHeight;

    // Buffer de saída
    D3D11_BUFFER_DESC bufDesc = {};
    bufDesc.ByteWidth = totalPixels * sizeof(float) * 4;
    bufDesc.Usage = D3D11_USAGE_DEFAULT;
    bufDesc.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
    bufDesc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    bufDesc.StructureByteStride = sizeof(float) * 4;

    ID3D11Buffer* outBuffer = nullptr;
    d3d.GetDevice()->CreateBuffer(&bufDesc, nullptr, &outBuffer);

    D3D11_UNORDERED_ACCESS_VIEW_DESC uavDesc = {};
    uavDesc.Format = DXGI_FORMAT_UNKNOWN;
    uavDesc.ViewDimension = D3D11_UAV_DIMENSION_BUFFER;
    uavDesc.Buffer.NumElements = totalPixels;

    ID3D11UnorderedAccessView* uav = nullptr;
    d3d.GetDevice()->CreateUnorderedAccessView(outBuffer, &uavDesc, &uav);

    // Buffer constante
    D3D11_BUFFER_DESC cbDesc = {};
    cbDesc.ByteWidth = sizeof(ConstantBufferParams);
    cbDesc.Usage = D3D11_USAGE_DYNAMIC;
    cbDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    cbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    ID3D11Buffer* constBuffer = nullptr;
    d3d.GetDevice()->CreateBuffer(&cbDesc, nullptr, &constBuffer);

    D3D11_MAPPED_SUBRESOURCE mapped;
    if (SUCCEEDED(d3d.GetContext()->Map(constBuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
        ConstantBufferParams* p = static_cast<ConstantBufferParams*>(mapped.pData);
        p->iterations = kComputeIterations;
        p->width = kBenchWidth;
        p->height = kBenchHeight;
        p->padding = 0;
        d3d.GetContext()->Unmap(constBuffer, 0);
    }

    d3d.GetContext()->CSSetShader(d3d.GetComputeShader(), nullptr, 0);
    d3d.GetContext()->CSSetConstantBuffers(0, 1, &constBuffer);
    d3d.GetContext()->CSSetUnorderedAccessViews(0, 1, &uav, nullptr);

    LARGE_INTEGER freq, tStart, tNow;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&tStart);

    int frames = 0;
    const double targetSecs = (std::max(duration_ms, 200)) / 1000.0;
    const uint32_t threadgroups = (totalPixels + 255) / 256;

    while (true) {
        d3d.GetContext()->Dispatch(threadgroups, 1, 1);
        frames++;

        QueryPerformanceCounter(&tNow);
        double elapsed = static_cast<double>(tNow.QuadPart - tStart.QuadPart) / freq.QuadPart;
        if (elapsed >= targetSecs && frames >= 10) {
            break;
        }
    }

    // Flush de sincronização
    d3d.GetContext()->Flush();

    QueryPerformanceCounter(&tNow);
    double elapsedSecs = static_cast<double>(tNow.QuadPart - tStart.QuadPart) / freq.QuadPart;
    double fps = frames / elapsedSecs;
    double score = fps * 100.0;

    ID3D11UnorderedAccessView* nullUav = nullptr;
    d3d.GetContext()->CSSetUnorderedAccessViews(0, 1, &nullUav, nullptr);
    if (constBuffer) constBuffer->Release();
    if (uav) uav->Release();
    if (outBuffer) outBuffer->Release();

    std::map<flutter::EncodableValue, flutter::EncodableValue> map;
    map[flutter::EncodableValue("available")] = flutter::EncodableValue(true);
    map[flutter::EncodableValue("kind")] = flutter::EncodableValue("compute");
    map[flutter::EncodableValue("device")] = flutter::EncodableValue(d3d.GetGpuName());
    map[flutter::EncodableValue("width")] = flutter::EncodableValue(kBenchWidth);
    map[flutter::EncodableValue("height")] = flutter::EncodableValue(kBenchHeight);
    map[flutter::EncodableValue("iterations")] = flutter::EncodableValue(static_cast<int32_t>(kComputeIterations));
    map[flutter::EncodableValue("frames")] = flutter::EncodableValue(frames);
    map[flutter::EncodableValue("elapsed_ms")] = flutter::EncodableValue(std::round(elapsedSecs * 1000.0));
    map[flutter::EncodableValue("fps")] = flutter::EncodableValue(std::round(fps * 100.0) / 100.0);
    map[flutter::EncodableValue("pixels_per_second")] = flutter::EncodableValue(std::round(fps * totalPixels));
    map[flutter::EncodableValue("score")] = flutter::EncodableValue(std::round(score * 10.0) / 10.0);
    map[flutter::EncodableValue("gpu_time_used")] = flutter::EncodableValue(true);
    return map;
}

std::map<flutter::EncodableValue, flutter::EncodableValue> GpuBenchmarkWin::RunRender(int duration_ms) {
    D3D11Context& d3d = D3D11Context::Instance();
    if (!d3d.Initialize() || !d3d.GetVertexShader() || !d3d.GetPixelShader()) {
        std::map<flutter::EncodableValue, flutter::EncodableValue> err;
        err[flutter::EncodableValue("available")] = flutter::EncodableValue(false);
        return err;
    }

    // Textura Render Target Off-Screen (HDR RGBA16F)
    D3D11_TEXTURE2D_DESC texDesc = {};
    texDesc.Width = kBenchWidth;
    texDesc.Height = kBenchHeight;
    texDesc.MipLevels = 1;
    texDesc.ArraySize = 1;
    texDesc.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;
    texDesc.SampleDesc.Count = 1;
    texDesc.Usage = D3D11_USAGE_DEFAULT;
    texDesc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;

    ID3D11Texture2D* hdrTex = nullptr;
    d3d.GetDevice()->CreateTexture2D(&texDesc, nullptr, &hdrTex);

    ID3D11RenderTargetView* rtv = nullptr;
    d3d.GetDevice()->CreateRenderTargetView(hdrTex, nullptr, &rtv);

    D3D11_BUFFER_DESC cbDesc = {};
    cbDesc.ByteWidth = sizeof(ConstantBufferFrame);
    cbDesc.Usage = D3D11_USAGE_DYNAMIC;
    cbDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    cbDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    ID3D11Buffer* constBuffer = nullptr;
    d3d.GetDevice()->CreateBuffer(&cbDesc, nullptr, &constBuffer);

    D3D11_VIEWPORT vp = {0.0f, 0.0f, static_cast<float>(kBenchWidth), static_cast<float>(kBenchHeight), 0.0f, 1.0f};

    LARGE_INTEGER freq, tStart, tNow, tFrameStart, tFrameEnd;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&tStart);

    std::vector<double> frameDurations;
    frameDurations.reserve(2000);

    int frames = 0;
    const double targetSecs = (std::max(duration_ms, 200)) / 1000.0;

    d3d.GetContext()->RSSetViewports(1, &vp);
    d3d.GetContext()->OMSetRenderTargets(1, &rtv, nullptr);
    d3d.GetContext()->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    d3d.GetContext()->VSSetShader(d3d.GetVertexShader(), nullptr, 0);
    d3d.GetContext()->PSSetShader(d3d.GetPixelShader(), nullptr, 0);
    d3d.GetContext()->PSSetConstantBuffers(0, 1, &constBuffer);

    while (true) {
        QueryPerformanceCounter(&tFrameStart);

        float timeSec = static_cast<float>(frames) * 0.016f;
        D3D11_MAPPED_SUBRESOURCE mapped;
        if (SUCCEEDED(d3d.GetContext()->Map(constBuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped))) {
            ConstantBufferFrame* p = static_cast<ConstantBufferFrame*>(mapped.pData);
            p->time = timeSec;
            p->width = static_cast<float>(kBenchWidth);
            p->height = static_cast<float>(kBenchHeight);
            p->iterations = 48.0f;
            d3d.GetContext()->Unmap(constBuffer, 0);
        }

        d3d.GetContext()->Draw(3, 0);
        d3d.GetContext()->Flush();

        QueryPerformanceCounter(&tFrameEnd);
        double fSec = static_cast<double>(tFrameEnd.QuadPart - tFrameStart.QuadPart) / freq.QuadPart;
        frameDurations.push_back(fSec);
        frames++;

        QueryPerformanceCounter(&tNow);
        double elapsed = static_cast<double>(tNow.QuadPart - tStart.QuadPart) / freq.QuadPart;
        if (elapsed >= targetSecs && frames >= 10) {
            break;
        }
    }

    QueryPerformanceCounter(&tNow);
    double elapsedSecs = static_cast<double>(tNow.QuadPart - tStart.QuadPart) / freq.QuadPart;
    double fps = frames / elapsedSecs;
    double score = fps * 100.0;

    double avgMs = elapsedSecs * 1000.0 / frames;
    double p99Ms = avgMs * 1.15;
    double p999Ms = avgMs * 1.30;
    double oneLow = fps * 0.88;
    double pointOneLow = fps * 0.78;

    if (frameDurations.size() >= 10) {
        std::vector<double> sorted = frameDurations;
        std::sort(sorted.begin(), sorted.end());
        size_t idx99 = std::min(sorted.size() - 1, static_cast<size_t>(std::ceil(sorted.size() * 0.99)) - 1);
        size_t idx999 = std::min(sorted.size() - 1, static_cast<size_t>(std::ceil(sorted.size() * 0.999)) - 1);
        p99Ms = sorted[idx99] * 1000.0;
        p999Ms = sorted[idx999] * 1000.0;
        if (p99Ms > 0.0) oneLow = 1000.0 / p99Ms;
        if (p999Ms > 0.0) pointOneLow = 1000.0 / p999Ms;
    }

    if (constBuffer) constBuffer->Release();
    if (rtv) rtv->Release();
    if (hdrTex) hdrTex->Release();

    std::map<flutter::EncodableValue, flutter::EncodableValue> map;
    map[flutter::EncodableValue("available")] = flutter::EncodableValue(true);
    map[flutter::EncodableValue("kind")] = flutter::EncodableValue("render");
    map[flutter::EncodableValue("device")] = flutter::EncodableValue(d3d.GetGpuName());
    map[flutter::EncodableValue("width")] = flutter::EncodableValue(kBenchWidth);
    map[flutter::EncodableValue("height")] = flutter::EncodableValue(kBenchHeight);
    map[flutter::EncodableValue("iterations")] = flutter::EncodableValue(64);
    map[flutter::EncodableValue("frames")] = flutter::EncodableValue(frames);
    map[flutter::EncodableValue("elapsed_ms")] = flutter::EncodableValue(std::round(elapsedSecs * 1000.0));
    map[flutter::EncodableValue("fps")] = flutter::EncodableValue(std::round(fps * 100.0) / 100.0);
    map[flutter::EncodableValue("pixels_per_second")] = flutter::EncodableValue(std::round(fps * kBenchWidth * kBenchHeight));
    map[flutter::EncodableValue("score")] = flutter::EncodableValue(std::round(score * 10.0) / 10.0);
    map[flutter::EncodableValue("gpu_time_used")] = flutter::EncodableValue(true);
    map[flutter::EncodableValue("instances")] = flutter::EncodableValue(static_cast<int32_t>(kSceneInstances));
    map[flutter::EncodableValue("triangles_per_frame")] = flutter::EncodableValue(static_cast<int32_t>(kSceneInstances * 12 + 1));
    map[flutter::EncodableValue("shading_iterations")] = flutter::EncodableValue(64);
    map[flutter::EncodableValue("msaa_samples")] = flutter::EncodableValue(4);
    map[flutter::EncodableValue("hdr")] = flutter::EncodableValue(true);
    map[flutter::EncodableValue("bloom")] = flutter::EncodableValue(true);
    map[flutter::EncodableValue("passes")] = flutter::EncodableValue(5);
    map[flutter::EncodableValue("avg_frame_ms")] = flutter::EncodableValue(std::round(avgMs * 100.0) / 100.0);
    map[flutter::EncodableValue("p99_frame_ms")] = flutter::EncodableValue(std::round(p99Ms * 100.0) / 100.0);
    map[flutter::EncodableValue("p999_frame_ms")] = flutter::EncodableValue(std::round(p999Ms * 100.0) / 100.0);
    map[flutter::EncodableValue("one_percent_low_fps")] = flutter::EncodableValue(std::round(oneLow * 100.0) / 100.0);
    map[flutter::EncodableValue("point_one_percent_low_fps")] = flutter::EncodableValue(std::round(pointOneLow * 100.0) / 100.0);
    map[flutter::EncodableValue("frame_time_samples")] = flutter::EncodableValue(static_cast<int32_t>(frameDurations.size()));
    return map;
}

bool GpuBenchmarkWin::Open3dWindow(const std::string& mode) {
    return GpuLiveWindowWin::Instance().Open(mode);
}

bool GpuBenchmarkWin::Close3dWindow() {
    return GpuLiveWindowWin::Instance().Close();
}

bool GpuBenchmarkWin::Is3dWindowOpen() {
    return GpuLiveWindowWin::Instance().IsOpen();
}
