// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import SafariServices
import UIKit

@MainActor
final class PhoneBrowser: NSObject, SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  private weak var safari: SFSafariViewController?
  private var finished: ((Bool) -> Void)?
  var coversTerminal: Bool { finished != nil }

  func open(_ address: String, external: Bool, from presenter: UIViewController, done: @escaping (Bool) -> Void) {
    guard finished == nil, presenter.viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive,
          address.utf8.count <= 32768, let url = URL(string: address),
          ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host, !host.isEmpty
    else { done(false); return }
    if external {
      UIApplication.shared.open(url, options: [:], completionHandler: done)
      return
    }
    guard presenter.presentedViewController == nil else { done(false); return }
    let view = SFSafariViewController(url: url)
    view.dismissButtonStyle = .done
    view.delegate = self
    safari = view
    finished = done
    presenter.present(view, animated: true)
    view.presentationController?.delegate = self
  }

  private func finish() {
    let done = finished
    finished = nil
    safari = nil
    done?(true)
  }

  func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
    guard safari === controller else { return }
    controller.dismiss(animated: true) { self.finish() }
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    if presentationController.presentedViewController === safari { finish() }
  }
}
