import AVFoundation
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var cameraCaptureSession: MacCameraSheetSession?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    self.title = "回响"

    let cameraChannel = FlutterMethodChannel(
      name: "com.dstweihao.echomind/camera",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    cameraChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      if call.method == "capturePhoto" {
        self.handleCapturePhoto(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func handleCapturePhoto(result: @escaping FlutterResult) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      presentCameraSheet(result: result)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          if granted {
            self?.presentCameraSheet(result: result)
          } else {
            result(
              FlutterError(
                code: "PERMISSION_DENIED",
                message: "未获得摄像头权限，请在系统设置 → 隐私与安全性 → 摄像头中允许「回响」访问",
                details: nil
              )
            )
          }
        }
      }
    default:
      result(
        FlutterError(
          code: "PERMISSION_DENIED",
          message: "未获得摄像头权限，请在系统设置 → 隐私与安全性 → 摄像头中允许「回响」访问",
          details: nil
        )
      )
    }
  }

  private func presentCameraSheet(result: @escaping FlutterResult) {
    guard let device = AVCaptureDevice.default(for: .video) else {
      result(
        FlutterError(
          code: "NO_CAMERA",
          message: "当前设备未检测到可用摄像头",
          details: nil
        )
      )
      return
    }

    let session = MacCameraSheetSession(parentWindow: self, device: device) { [weak self] outcome in
      self?.cameraCaptureSession = nil
      switch outcome {
      case .captured(let path):
        result(path)
      case .cancelled:
        result(nil)
      case .failed(let message):
        result(FlutterError(code: "CAPTURE_FAILED", message: message, details: nil))
      }
    }
    self.cameraCaptureSession = session
    session.present()
  }
}

private enum MacCameraOutcome {
  case captured(String)
  case cancelled
  case failed(String)
}

private final class MacCameraSheetSession: NSObject, AVCapturePhotoCaptureDelegate {
  private weak var parentWindow: NSWindow?
  private let device: AVCaptureDevice
  private let completion: (MacCameraOutcome) -> Void

  private let captureSession = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private var sheetWindow: NSWindow?
  private var captureButton: NSButton?
  private var finished = false

  init(
    parentWindow: NSWindow,
    device: AVCaptureDevice,
    completion: @escaping (MacCameraOutcome) -> Void
  ) {
    self.parentWindow = parentWindow
    self.device = device
    self.completion = completion
    super.init()
  }

  func present() {
    do {
      let input = try AVCaptureDeviceInput(device: device)
      captureSession.beginConfiguration()
      captureSession.sessionPreset = .photo
      if captureSession.canAddInput(input) {
        captureSession.addInput(input)
      }
      if captureSession.canAddOutput(photoOutput) {
        captureSession.addOutput(photoOutput)
      }
      captureSession.commitConfiguration()
    } catch {
      finish(.failed("无法初始化摄像头：\(error.localizedDescription)"))
      return
    }

    let width: CGFloat = 520
    let height: CGFloat = 420
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    panel.title = "拍照"

    let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.black.cgColor

    let previewContainer = NSView(frame: NSRect(x: 0, y: 64, width: width, height: height - 64))
    previewContainer.wantsLayer = true
    let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    previewLayer.videoGravity = .resizeAspectFill
    previewLayer.frame = previewContainer.bounds
    previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    previewContainer.layer?.addSublayer(previewLayer)
    root.addSubview(previewContainer)

    let bar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 64))
    bar.wantsLayer = true
    bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    let cancelBtn = NSButton(title: "取消", target: self, action: #selector(onCancel))
    cancelBtn.bezelStyle = .rounded
    cancelBtn.frame = NSRect(x: 20, y: 16, width: 88, height: 32)
    bar.addSubview(cancelBtn)

    let snapBtn = NSButton(title: "拍照", target: self, action: #selector(onCapture))
    snapBtn.bezelStyle = .rounded
    snapBtn.keyEquivalent = "\r"
    snapBtn.frame = NSRect(x: width - 116, y: 16, width: 96, height: 32)
    bar.addSubview(snapBtn)
    self.captureButton = snapBtn

    root.addSubview(bar)
    panel.contentView = root
    self.sheetWindow = panel

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.captureSession.startRunning()
    }

    if let parent = parentWindow {
      parent.beginSheet(panel) { [weak self] _ in
        self?.stopSession()
      }
    } else {
      panel.makeKeyAndOrderFront(nil)
    }
  }

  @objc private func onCancel() {
    finish(.cancelled)
  }

  @objc private func onCapture() {
    captureButton?.isEnabled = false
    let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    if let error = error {
      finish(.failed("拍照失败：\(error.localizedDescription)"))
      return
    }
    guard let data = photo.fileDataRepresentation() else {
      finish(.failed("未能读取照片数据"))
      return
    }
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("echomind_camera_\(UUID().uuidString).jpg")
    do {
      try data.write(to: fileURL, options: .atomic)
      finish(.captured(fileURL.path))
    } catch {
      finish(.failed("保存照片失败：\(error.localizedDescription)"))
    }
  }

  private func stopSession() {
    if captureSession.isRunning {
      DispatchQueue.global(qos: .utility).async { [weak self] in
        self?.captureSession.stopRunning()
      }
    }
  }

  private func finish(_ outcome: MacCameraOutcome) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, !self.finished else { return }
      self.finished = true
      self.stopSession()
      if let panel = self.sheetWindow {
        if let parent = self.parentWindow {
          parent.endSheet(panel)
        }
        panel.orderOut(nil)
        self.sheetWindow = nil
      }
      self.completion(outcome)
    }
  }
}
