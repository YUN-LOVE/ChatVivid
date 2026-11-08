//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <dynamic_color/dynamic_color_plugin_c_api.h>
#include <flutter_tts/flutter_tts_plugin.h>
#include <live2d_flutter/flutter_live2d_plugin_c_api.h>
#include <rive_native/rive_native_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  DynamicColorPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DynamicColorPluginCApi"));
  FlutterTtsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterTtsPlugin"));
  FlutterLive2dPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterLive2dPluginCApi"));
  RiveNativePluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("RiveNativePlugin"));
}
