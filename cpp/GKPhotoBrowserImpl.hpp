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
      const std::function<void()>& onDismiss,
      const std::function<void(double)>& onDownload,
      const std::function<void(double)>& onForward) override;

  void dismiss() override;

 private:
  std::unique_ptr<GKPhotoBrowserRuntime> runtime_;
};

} // namespace margelo::nitro::gkphotobrowser
