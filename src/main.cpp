#include <curl/curl.h>

#include <csignal>
#include <filesystem>
#include <iostream>
#include <string>

#include "app/config.h"
#include "context/injections.h"
#include "dialog/dialog_service.h"
#include "dialog/response_hub.h"
#include "http/server.h"
#include "llm/provider.h"
#include "store/db.h"
#include "util/log.h"

namespace {

chatvv::HttpServer* g_server = nullptr;

void on_signal(int) {
  if (g_server) g_server->stop();
}

}  // namespace

int main(int argc, char** argv) {
  std::string config_path = "config/config.toml";
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if ((arg == "--config" || arg == "-c") && i + 1 < argc) {
      config_path = argv[++i];
    } else if (arg == "--help" || arg == "-h") {
      std::cout << "chatvvd [--config path]\n";
      return 0;
    }
  }

  try {
    auto cfg = chatvv::Config::load(config_path);
    const std::filesystem::path data_dir(cfg.storage.data_dir);
    std::filesystem::create_directories(data_dir);
    chatvv::init_log(chatvv::LogLevel::Info, data_dir / "chatvv.log");

    curl_global_init(CURL_GLOBAL_DEFAULT);

    chatvv::Db db(cfg.db_path());
    db.migrate();

    chatvv::InjectionStore slots;
    slots.load_dir(cfg.injections.dir);

    auto provider = chatvv::make_provider(cfg);
    chatvv::ResponseHub hub;
    chatvv::DialogService dialog(cfg, db, slots, hub, *provider);
    chatvv::HttpServer server(cfg, db, slots, hub, dialog);

    g_server = &server;
    std::signal(SIGINT, on_signal);
    std::signal(SIGTERM, on_signal);

    chatvv::log_info("chatvvd.start",
                     {{"data_dir", cfg.storage.data_dir},
                      {"provider", cfg.llm.provider},
                      {"injections", slots.all().size()}});

    const bool ok = server.listen();
    g_server = nullptr;
    dialog.shutdown();
    curl_global_cleanup();
    return ok ? 0 : 1;
  } catch (const std::exception& e) {
    std::cerr << "fatal: " << e.what() << "\n";
    return 1;
  }
}
