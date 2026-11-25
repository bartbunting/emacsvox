// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import CryptoKit
import Foundation
import OmnivoxMobile
import UIKit
import UniformTypeIdentifiers

enum CueImportError: Error { case busy, format, size, recording }

final class CueImport: NSObject, UIDocumentPickerDelegate {
  private var answer: ((Result<Bool, Error>) -> Void)?
  static func root() throws -> URL {
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                            appropriateFor: nil, create: true).appendingPathComponent("OmnivoxCues")
    try FileManager.default.createDirectory(at: base.appendingPathComponent("personal"), withIntermediateDirectories: true)
    return base
  }

  func pick(from controller: UIViewController, done: @escaping (Result<Bool, Error>) -> Void) throws {
    guard answer == nil else { throw CueImportError.busy }
    let types = ["wav", "ogg"].compactMap { UTType(filenameExtension: $0) }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    picker.delegate = self
    answer = done
    controller.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let done = answer
    answer = nil
    done?(.success(false))
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first, let done = answer else { documentPickerWasCancelled(controller); return }
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result { try Self.store(url); return true }
      DispatchQueue.main.async { self.answer = nil; done(result) }
    }
  }

  private static func store(_ url: URL) throws {
    let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    let limit = 16 * 1024 * 1024
    guard info.isRegularFile == true, let size = info.fileSize, size > 0, size <= limit else { throw CueImportError.size }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    guard let data = try file.read(upToCount: limit + 1), data.count == size else { throw CueImportError.size }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let root = try Self.root()
    let target = root.appendingPathComponent("personal/" + digest)
    if FileManager.default.fileExists(atPath: target.path) { return }
    // Validate the exact bytes with the playback decoder before publishing
    // their digest. An oversized decoded recording never becomes available.
    let name = UUID().uuidString
    let temp = root.appendingPathComponent(name)
    try data.write(to: temp, options: .atomic)
    defer { try? FileManager.default.removeItem(at: temp) }
    guard let loader = ov_ios_loader_new(root.path) else { throw CueImportError.recording }
    defer { ov_ios_loader_free(loader) }
    let token = ov_ios_token_new()!
    defer { ov_ios_token_free(token) }
    guard let pcm = ov_ios_sound(loader, "omnivox-icon:" + name, 1, token) else { throw CueImportError.format }
    defer { ov_ios_pcm_free(pcm) }
    guard ov_ios_frames(pcm) > 0 else { throw CueImportError.recording }
    try FileManager.default.moveItem(at: temp, to: target)
  }
}
