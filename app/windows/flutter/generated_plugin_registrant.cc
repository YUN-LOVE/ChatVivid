//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <live2d_flutter/flutter_live2d_plugin_c_api.h>
#include <rive_native/rive_native_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterLive2dPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterLive2dPluginCApi"));
  RiveNativePluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("RiveNativePlugin"));
}
