//
//  LowResNXViewController.swift
//  LowRes NX iOS
//
//  Created by Timo Kloss on 1/9/17.
//  Copyright © 2017 Inutilis Software. All rights reserved.
//

import UIKit
import GameController

class LowResNXViewController: UIViewController, UIKeyInput, CoreWrapperDelegate {
    
    @IBOutlet private weak var exitButton: UIButton!
    @IBOutlet private weak var zoomButton: UIButton!
    @IBOutlet private weak var soundButton: UIButton!
    @IBOutlet private weak var nxView: LowResNXView!
    @IBOutlet private weak var containerView: UIView!
    @IBOutlet private weak var widthConstraint: NSLayoutConstraint!
    @IBOutlet private weak var keyboardConstraint: NSLayoutConstraint!
    
    var document: ProjectDocument?
    
    private var coreWrapper = CoreWrapper()
    private var displayLink: CADisplayLink?
    private var compilerError: Error?
    
    private var pixelExactScaling: Bool = true {
        didSet {
            view.setNeedsLayout()
            let image = UIImage(named:pixelExactScaling ? "zoom_off" : "zoom_on")
            zoomButton.setImage(image, for: .normal)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let sourceCode = document?.sourceCode {
            let cString = sourceCode.cString(using: .ascii)
            let error = itp_compileProgram(&coreWrapper.core, cString)
            if error.code != ErrorNone {
                compilerError = LowResNXError(error: error, sourceCode: sourceCode)
            }
        }
        
        nxView.coreWrapper = coreWrapper
        
        coreWrapper.delegate = self
        core_willRunProgram(&coreWrapper.core, 0)
        configureGameControllers()
        
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(recognizer)
        
        let displayLink = CADisplayLink(target: self, selector: #selector(update))
        self.displayLink = displayLink
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: .UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: .UIKeyboardWillHide, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDidConnect), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDidDisconnect), name: .GCControllerDidDisconnect, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        displayLink!.add(to: .current, forMode: .defaultRunLoopMode)
        if let error = compilerError {
            let alert = UIAlertController(title: "Cannot Run Program", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.endEditing(true)
    }
    
    override var prefersStatusBarHidden: Bool {
        if #available(iOS 11.0, *) {
            if let window = UIApplication.shared.delegate?.window {
                if window?.safeAreaInsets.top != 0 {
                    return false
                }
            }
        }
        return true
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let screenWidth = containerView.bounds.size.width
        let screenHeight = containerView.bounds.size.height
        var maxWidthFactor: CGFloat
        var maxHeightFactor: CGFloat
        if pixelExactScaling {
            let scale: CGFloat = view.window?.screen.scale ?? 1.0
            maxWidthFactor = floor(screenWidth * scale / CGFloat(SCREEN_WIDTH)) / scale
            maxHeightFactor = floor(screenHeight * scale / CGFloat(SCREEN_HEIGHT)) / scale
        } else {
            maxWidthFactor = screenWidth / CGFloat(SCREEN_WIDTH)
            maxHeightFactor = screenHeight / CGFloat(SCREEN_HEIGHT)
        }
        widthConstraint.constant = (maxWidthFactor < maxHeightFactor) ? maxWidthFactor * CGFloat(SCREEN_WIDTH) : maxHeightFactor * CGFloat(SCREEN_WIDTH)
    }
    
    @objc func update(displaylink: CADisplayLink) {
        updateGameControllers()
        core_update(&coreWrapper.core)
        nxView.render()
    }
    
    func configureGameControllers() {
        let gameControllers = GCController.controllers()
        
        core_setNumPhysicalGamepads(&coreWrapper.core, Int32(gameControllers.count))
        
        var count = 0
        for gameController in gameControllers {
            gameController.playerIndex = GCControllerPlayerIndex(rawValue: count)!
            gameController.controllerPausedHandler = { [weak self] (controller) in
                if let coreWrapper = self?.coreWrapper {
                    core_pausePressed(&coreWrapper.core)
                }
            }
            count += 1
        }
    }
    
    func updateGameControllers() {
        for gameController in GCController.controllers() {
            if let gamepad = gameController.gamepad, gameController.playerIndex != .indexUnset {
                var up = gamepad.dpad.up.isPressed
                var down = gamepad.dpad.down.isPressed
                var left = gamepad.dpad.left.isPressed
                var right = gamepad.dpad.right.isPressed
                if let stick = gameController.extendedGamepad?.leftThumbstick {
                    up = up || stick.up.isPressed
                    down = down || stick.down.isPressed
                    left = left || stick.left.isPressed
                    right = right || stick.right.isPressed
                }
                let buttonA = gamepad.buttonA.isPressed || gamepad.buttonX.isPressed
                let buttonB = gamepad.buttonB.isPressed || gamepad.buttonY.isPressed
                core_setGamepad(&coreWrapper.core, Int32(gameController.playerIndex.rawValue), up, down, left, right, buttonA, buttonB)
            }
        }
    }
    
    @objc func handleTap(sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            if core_getKeyboardEnabled(&coreWrapper.core) {
                becomeFirstResponder()
            }
        }
    }
    
    override var canBecomeFirstResponder: Bool {
        return core_getKeyboardEnabled(&coreWrapper.core)
    }
    
    @objc func keyboardWillShow(_ notification: NSNotification) {
        if let frameValue = notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue {
            let frame = frameValue.cgRectValue
            keyboardConstraint.constant = view.bounds.size.height - frame.origin.y
            UIView.animate(withDuration: 0.3, animations: { 
                self.view.layoutIfNeeded()
            })
        }
    }

    @objc func keyboardWillHide(_ notification: NSNotification) {
        keyboardConstraint.constant = 0
        UIView.animate(withDuration: 0.3, animations: {
            self.view.layoutIfNeeded()
        })
    }
    
    @objc func controllerDidConnect(_ notification: NSNotification) {
        configureGameControllers()
    }

    @objc func controllerDidDisconnect(_ notification: NSNotification) {
        configureGameControllers()
    }
    
    @IBAction func onExitTapped(_ sender: Any) {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func onZoomTapped(_ sender: Any) {
        pixelExactScaling = !pixelExactScaling
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func onSoundTapped(_ sender: Any) {
    }
    
    // MARK: - Core Wrapper Delegate
    
    func coreInterpreterDidFail(coreError: CoreError) {
        let interpreterError = LowResNXError(error: coreError, sourceCode: document!.sourceCode!)
        let alert = UIAlertController(title: "Runtime Error", message: interpreterError.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    func coreDiskDriveWillAccess(diskDataManager: UnsafeMutablePointer<DataManager>?) -> Bool {
        return true
    }
    
    func coreDiskDriveDidSave(diskDataManager: UnsafeMutablePointer<DataManager>?) {
    }
    
    func coreControlsDidChange(controlsInfo: ControlsInfo) {
        DispatchQueue.main.async {
            if controlsInfo.isKeyboardEnabled {
                self.becomeFirstResponder()
            } else {
                self.resignFirstResponder()
            }
        }
    }
    
    // MARK: - UIKeyInput
    
    var autocorrectionType: UITextAutocorrectionType = .no
    var spellCheckingType: UITextSpellCheckingType = .no
    var keyboardAppearance: UIKeyboardAppearance = .dark
    
    var hasText: Bool {
        return true
    }
    
    func insertText(_ text: String) {
        if text == "\n" {
            core_returnPressed(&coreWrapper.core)
        } else if let key = text.uppercased().unicodeScalars.first?.value {
            if key < 127 {
                core_keyPressed(&coreWrapper.core, Int8(key))
            }
        }
    }
    
    func deleteBackward() {
        core_backspacePressed(&coreWrapper.core)
    }
    
    // this is from UITextInput, needed because of crash on iPhone 6 keyboard (left/right arrows)
    var selectedTextRange: UITextRange? {
        return nil
    }
    
}

