#include <CubismFramework.hpp>
#include <CubismModelSettingJson.hpp>
#include <ICubismAllocator.hpp>
#include <Model/CubismMoc.hpp>
#include <Model/CubismModel.hpp>
#include <Rendering/D3D11/CubismDeviceInfo_D3D11.hpp>
#include <Rendering/D3D11/CubismRenderer_D3D11.hpp>

#include <d3d11.h>
#include <malloc.h>
#include <windows.h>
#include <wrl/client.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

namespace Csm = Live2D::Cubism::Framework;
namespace Rendering = Live2D::Cubism::Framework::Rendering;
using Microsoft::WRL::ComPtr;

namespace {

std::filesystem::path g_executable_directory;

class SmokeAllocator final : public Csm::ICubismAllocator {
 public:
  void* Allocate(Csm::csmSizeType size) override { return malloc(size); }
  void Deallocate(void* memory) override { free(memory); }
  void* AllocateAligned(Csm::csmSizeType size,
                        Csm::csmUint32 alignment) override {
    return _aligned_malloc(size, alignment);
  }
  void DeallocateAligned(void* memory) override { _aligned_free(memory); }
};

std::filesystem::path ExecutableDirectory() {
  wchar_t path[MAX_PATH] = {};
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return {};
  return std::filesystem::path(std::wstring(path, length)).parent_path();
}

std::filesystem::path ResolvePath(const std::string& path) {
  std::filesystem::path resolved(path);
  if (resolved.is_relative()) resolved = g_executable_directory / resolved;
  return resolved.lexically_normal();
}

Csm::csmByte* LoadFile(const std::string path, Csm::csmSizeInt* out_size) {
  *out_size = 0;
  const std::filesystem::path resolved = ResolvePath(path);
  std::ifstream stream(resolved, std::ios::binary | std::ios::ate);
  if (!stream) {
    std::cerr << "[NATIVE-SMOKE] FILE_FAIL " << resolved.string() << '\n';
    return nullptr;
  }
  const std::streamsize length = stream.tellg();
  if (length <= 0 || length > INT_MAX) return nullptr;
  stream.seekg(0, std::ios::beg);
  auto* bytes = new Csm::csmByte[static_cast<size_t>(length)];
  if (!stream.read(reinterpret_cast<char*>(bytes), length)) {
    delete[] bytes;
    return nullptr;
  }
  *out_size = static_cast<Csm::csmSizeInt>(length);
  std::cout << "[NATIVE-SMOKE] FILE_OK bytes=" << length
            << " path=" << resolved.string() << '\n';
  return bytes;
}

void ReleaseFile(Csm::csmByte* bytes) { delete[] bytes; }

void Log(const Csm::csmChar* message) {
  if (!message) return;
  std::cout << "[NATIVE-SMOKE] " << message;
  std::cout.flush();
}

int RunSmoke(const std::filesystem::path& model_json) {
  Csm::csmSizeInt json_size = 0;
  Csm::csmByte* json_bytes =
      LoadFile(model_json.string(), &json_size);
  if (!json_bytes) return 10;
  auto setting =
      std::make_unique<Csm::CubismModelSettingJson>(json_bytes, json_size);
  ReleaseFile(json_bytes);
  std::cout << "[NATIVE-SMOKE] MODEL_JSON_OK textures="
            << setting->GetTextureCount()
            << " expressions=" << setting->GetExpressionCount()
            << " motionGroups=" << setting->GetMotionGroupCount() << '\n';

  const std::filesystem::path model_directory = model_json.parent_path();
  for (Csm::csmInt32 i = 0; i < setting->GetTextureCount(); ++i) {
    const std::filesystem::path texture =
        model_directory / setting->GetTextureFileName(i);
    if (!std::filesystem::is_regular_file(texture)) {
      std::cerr << "[NATIVE-SMOKE] TEXTURE_MISSING " << texture.string()
                << '\n';
      return 11;
    }
  }
  std::cout << "[NATIVE-SMOKE] TEXTURE_FILES_OK count="
            << setting->GetTextureCount() << '\n';

  const std::filesystem::path moc_path =
      model_directory / setting->GetModelFileName();
  Csm::csmSizeInt moc_size = 0;
  Csm::csmByte* moc_bytes = LoadFile(moc_path.string(), &moc_size);
  if (!moc_bytes) return 12;
  Csm::CubismMoc* moc = Csm::CubismMoc::Create(moc_bytes, moc_size, true);
  ReleaseFile(moc_bytes);
  if (!moc) {
    std::cerr << "[NATIVE-SMOKE] MOC_FAIL\n";
    return 13;
  }
  std::cout << "[NATIVE-SMOKE] MOC_OK bytes=" << moc_size << '\n';

  Csm::CubismModel* model = moc->CreateModel();
  if (!model) {
    Csm::CubismMoc::Delete(moc);
    std::cerr << "[NATIVE-SMOKE] MODEL_FAIL\n";
    return 14;
  }
  std::cout << "[NATIVE-SMOKE] MODEL_OK canvas=" << model->GetCanvasWidth()
            << 'x' << model->GetCanvasHeight()
            << " parameters=" << model->GetParameterCount()
            << " drawables=" << model->GetDrawableCount() << '\n';

  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  constexpr D3D_FEATURE_LEVEL feature_levels[] = {
      D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
  D3D_FEATURE_LEVEL feature_level;
  UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
#ifdef _DEBUG
  flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif
  HRESULT result = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, feature_levels,
      ARRAYSIZE(feature_levels), D3D11_SDK_VERSION, device.GetAddressOf(),
      &feature_level, context.GetAddressOf());
  if (FAILED(result)) {
    flags &= ~D3D11_CREATE_DEVICE_DEBUG;
    result = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags, feature_levels,
        ARRAYSIZE(feature_levels), D3D11_SDK_VERSION, device.GetAddressOf(),
        &feature_level, context.GetAddressOf());
  }
  if (FAILED(result)) {
    moc->DeleteModel(model);
    Csm::CubismMoc::Delete(moc);
    std::cerr << "[NATIVE-SMOKE] D3D_DEVICE_FAIL hr=0x" << std::hex
              << static_cast<unsigned int>(result) << '\n';
    return 15;
  }
  std::cout << "[NATIVE-SMOKE] D3D_DEVICE_OK featureLevel=0x" << std::hex
            << static_cast<unsigned int>(feature_level) << std::dec << '\n';

  Rendering::CubismRenderer_D3D11::SetConstantSettings(1, device.Get());
  Csm::Rendering::CubismRenderer* renderer =
      Csm::Rendering::CubismRenderer::Create(632, 520);
  renderer->Initialize(model, 1);
  std::cout << "[NATIVE-SMOKE] RENDERER_INITIALIZE_RETURNED\n";

  Rendering::CubismDeviceInfo_D3D11* device_info =
      Rendering::CubismDeviceInfo_D3D11::GetDeviceInfo(device.Get());
  const bool shader_ready =
      device_info->GetShader()->GetVertexShader(Csm::ShaderNames_Normal) !=
      nullptr;
  std::cout << "[NATIVE-SMOKE] SHADER_READY=" << shader_ready << '\n';

  Csm::Rendering::CubismRenderer::Delete(renderer);
  Rendering::CubismDeviceInfo_D3D11::ReleaseAllDeviceInfo();
  moc->DeleteModel(model);
  Csm::CubismMoc::Delete(moc);
  if (!shader_ready) return 16;

  std::cout << "[NATIVE-SMOKE] PASS\n";
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "Usage: native_live2d_smoke <model3.json>\n";
    return 2;
  }

  g_executable_directory = ExecutableDirectory();
  const std::filesystem::path model_json =
      std::filesystem::absolute(argv[1]).lexically_normal();
  std::cout << "[NATIVE-SMOKE] START model=" << model_json.string() << '\n';

  SmokeAllocator allocator;
  Csm::CubismFramework::Option option;
  option.LogFunction = Log;
  option.LoggingLevel = Csm::CubismFramework::Option::LogLevel_Info;
  option.LoadFileFunction = LoadFile;
  option.ReleaseBytesFunction = ReleaseFile;
  if (!Csm::CubismFramework::StartUp(&allocator, &option)) {
    std::cerr << "[NATIVE-SMOKE] FRAMEWORK_STARTUP_FAIL\n";
    return 3;
  }
  Csm::CubismFramework::Initialize();
  std::cout << "[NATIVE-SMOKE] FRAMEWORK_OK\n";

  const int result = RunSmoke(model_json);
  Csm::CubismFramework::Dispose();
  std::cout << "[NATIVE-SMOKE] EXIT code=" << result << std::endl;
  return result;
}
