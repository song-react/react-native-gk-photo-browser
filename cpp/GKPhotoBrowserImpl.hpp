#pragma once

#include "HybridGKPhotoBrowserSpec.hpp"
#include <memory>

namespace margelo::nitro::gkphotobrowser {

class GKPhotoBrowserRuntime;

class GKPhotoBrowserImpl final : public HybridGKPhotoBrowserSpec {
 public:
  GKPhotoBrowserImpl();
  ~GKPhotoBrowserImpl() override;

  void show(
      const BrowserConfig& config,
      const std::optional<BrowserCallbacks>& callbacks) override;

  void dismiss() override;

 private:
  std::unique_ptr<GKPhotoBrowserRuntime> runtime_;
};

} // namespace margelo::nitro::gkphotobrowser
