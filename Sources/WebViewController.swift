import UIKit

/// Full-screen web page driven by the Siri Remote:
///   swipe touch surface  -> move cursor (pushing against an edge scrolls)
///   click                -> click whatever is under the cursor
///   d-pad / arrows       -> scroll a page-ish chunk
///   Menu / Back          -> browser back (exits the app when there's no history)
///   Play/Pause           -> reload the home page
final class WebViewController: UIViewController {
    private var web: LegacyWebView?
    private let cursor = UIView()
    private let messageLabel = UILabel()
    private var cursorPosition = CGPoint.zero
    private var hideCursorWork: DispatchWorkItem?
    private var swallowMenuEnd = false

    private let handledPresses: Set<UIPress.PressType> = [
        .select, .playPause, .upArrow, .downArrow, .leftArrow, .rightArrow, .pageUp, .pageDown,
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setUpMessageLabel()

        guard let web = LegacyWebView() else {
            showMessage("This version of tvOS doesn't include a web view.")
            return
        }
        self.web = web
        web.view.frame = view.bounds
        web.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // We drive the page ourselves; the web view shouldn't grab remote input.
        web.view.isUserInteractionEnabled = false
        view.insertSubview(web.view, at: 0)

        web.onFinishLoad = { [weak self] in self?.messageLabel.isHidden = true }
        web.onFailLoad = { [weak self] error in
            self?.showMessage("Couldn't load the page.\n\(error.localizedDescription)\n\nPress Play/Pause to try again.")
        }

        setUpCursor()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(pan)

        web.load(Config.homeURL)
    }

    // MARK: - Cursor

    private func setUpCursor() {
        let size: CGFloat = 30
        cursor.frame = CGRect(x: 0, y: 0, width: size, height: size)
        cursor.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        cursor.layer.cornerRadius = size / 2
        cursor.layer.borderColor = UIColor.black.withAlphaComponent(0.6).cgColor
        cursor.layer.borderWidth = 2
        cursor.layer.shadowColor = UIColor.black.cgColor
        cursor.layer.shadowOpacity = 0.5
        cursor.layer.shadowRadius = 6
        cursor.isUserInteractionEnabled = false
        view.addSubview(cursor)

        cursorPosition = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        cursor.center = cursorPosition
        showCursor()
    }

    private func showCursor() {
        cursor.alpha = 1
        hideCursorWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.4) { self?.cursor.alpha = 0 }
        }
        hideCursorWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.cursorHideDelay, execute: work)
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let t = pan.translation(in: view)
        pan.setTranslation(.zero, in: view)
        moveCursor(dx: t.x * Config.cursorSpeed, dy: t.y * Config.cursorSpeed)
    }

    private func moveCursor(dx: CGFloat, dy: CGFloat) {
        let bounds = view.bounds
        let target = CGPoint(x: cursorPosition.x + dx, y: cursorPosition.y + dy)
        cursorPosition = CGPoint(x: min(max(target.x, 0), bounds.maxX),
                                 y: min(max(target.y, 0), bounds.maxY))
        cursor.center = cursorPosition
        showCursor()

        // Whatever didn't fit on screen becomes a scroll.
        let overflowX = target.x - cursorPosition.x
        let overflowY = target.y - cursorPosition.y
        if overflowX != 0 || overflowY != 0 {
            scroll(dx: overflowX * 2, dy: overflowY * 2)
        }
    }

    // MARK: - Page actions

    private func runPage(_ call: String) -> String {
        web?.evaluate(PageScript.prelude + call) ?? ""
    }

    private func click() {
        UIView.animate(withDuration: 0.08, animations: {
            self.cursor.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        }, completion: { _ in
            UIView.animate(withDuration: 0.08) { self.cursor.transform = .identity }
        })
        showCursor()

        let p = cursorPosition
        let result = runPage("window.__atv.click(\(p.x),\(p.y),\(view.bounds.width))")
        if let data = result.data(using: .utf8),
           let field = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            promptForText(field)
        }
    }

    private func scroll(dx: CGFloat, dy: CGFloat) {
        let p = cursorPosition
        _ = runPage("window.__atv.scroll(\(p.x),\(p.y),\(dx),\(dy),\(view.bounds.width))")
    }

    /// The remote has no keyboard, so text fields get the system text-entry screen.
    private func promptForText(_ field: [String: Any]) {
        let label = field["label"] as? String ?? ""
        let alert = UIAlertController(title: label.isEmpty ? "Enter text" : label, message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = field["value"] as? String
            tf.isSecureTextEntry = field["secure"] as? Bool ?? false
        }
        let submit = { [weak self, weak alert] (go: Bool) in
            let text = alert?.textFields?.first?.text ?? ""
            guard let args = try? JSONSerialization.data(withJSONObject: [text, go]),
                  let argsJS = String(data: args, encoding: .utf8) else { return }
            _ = self?.runPage("window.__atv.setText.apply(window.__atv,\(argsJS))")
        }
        alert.addAction(UIAlertAction(title: "Done & Go", style: .default) { _ in submit(true) })
        alert.addAction(UIAlertAction(title: "Done", style: .default) { _ in submit(false) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Remote buttons

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passOn = Set<UIPress>()
        let page = view.bounds.height * 0.6
        for press in presses {
            switch press.type {
            case .select: click()
            case .playPause: web?.load(Config.homeURL)
            case .upArrow: scroll(dx: 0, dy: -page)
            case .downArrow: scroll(dx: 0, dy: page)
            case .leftArrow: scroll(dx: -page, dy: 0)
            case .rightArrow: scroll(dx: page, dy: 0)
            case .pageUp: scroll(dx: 0, dy: -view.bounds.height * 0.9)
            case .pageDown: scroll(dx: 0, dy: view.bounds.height * 0.9)
            case .menu:
                if let web = web, web.canGoBack {
                    web.goBack()
                    swallowMenuEnd = true
                } else {
                    passOn.insert(press) // lets tvOS leave the app
                }
            default:
                passOn.insert(press)
            }
        }
        if !passOn.isEmpty { super.pressesBegan(passOn, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let passOn = unhandled(presses)
        if !passOn.isEmpty { super.pressesEnded(passOn, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let passOn = unhandled(presses)
        if !passOn.isEmpty { super.pressesCancelled(passOn, with: event) }
    }

    private func unhandled(_ presses: Set<UIPress>) -> Set<UIPress> {
        var passOn = Set<UIPress>()
        for press in presses {
            if press.type == .menu {
                if !swallowMenuEnd { passOn.insert(press) }
                swallowMenuEnd = false
            } else if !handledPresses.contains(press.type) {
                passOn.insert(press)
            }
        }
        return passOn
    }

    // MARK: - Messages

    private func setUpMessageLabel() {
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 38, weight: .medium)
        messageLabel.frame = view.bounds.insetBy(dx: 160, dy: 160)
        messageLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        messageLabel.isHidden = true
        view.addSubview(messageLabel)
    }

    private func showMessage(_ text: String) {
        messageLabel.text = text
        messageLabel.isHidden = false
    }
}

/// JavaScript helpers injected into whatever page is loaded.
/// Coordinates come in as screen points; `W` is the screen width in points,
/// which lets us convert to the page's CSS pixels however it's been scaled.
private enum PageScript {
    static let prelude = """
    if(!window.__atv){window.__atv={
     ratio:function(W){return (document.documentElement.clientWidth||window.innerWidth)/W;},
     click:function(x,y,W){
      var r=this.ratio(W),cx=x*r,cy=y*r,e=document.elementFromPoint(cx,cy);if(!e)return '';
      var t=e.closest('textarea,input,[contenteditable]');
      if(t&&!t.disabled&&!t.readOnly&&(t.tagName==='TEXTAREA'||t.isContentEditable||
         (t.tagName==='INPUT'&&/^(text|search|email|url|password|number|tel)$/.test(t.type)))){
       this.field=t;t.focus();
       return JSON.stringify({secure:t.type==='password',value:t.isContentEditable?t.innerText:t.value,
        label:t.getAttribute('aria-label')||t.placeholder||t.name||''});
      }
      var a=e.closest('a[target]');if(a)a.target='_self';
      var o={bubbles:true,cancelable:true,view:window,clientX:cx,clientY:cy};
      function fire(n,C){if(C)e.dispatchEvent(new C(n,o));}
      fire('pointerdown',window.PointerEvent);fire('mousedown',MouseEvent);
      fire('pointerup',window.PointerEvent);fire('mouseup',MouseEvent);fire('click',MouseEvent);
      if(e.focus)e.focus();
      return '';
     },
     scroll:function(x,y,dx,dy,W){
      var r=this.ratio(W);dx*=r;dy*=r;
      for(var e=document.elementFromPoint(x*r,y*r);e&&e!==document.body&&e!==document.documentElement;e=e.parentElement){
       var c=getComputedStyle(e);
       if((dy&&e.scrollHeight>e.clientHeight&&/auto|scroll/.test(c.overflowY))||
          (dx&&e.scrollWidth>e.clientWidth&&/auto|scroll/.test(c.overflowX))){e.scrollTop+=dy;e.scrollLeft+=dx;return;}
      }
      window.scrollBy(dx,dy);
     },
     setText:function(v,go){
      var t=this.field;if(!t)return;
      if(t.isContentEditable){t.innerText=v;}else{
       var d=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(t),'value');
       if(d&&d.set){d.set.call(t,v);}else{t.value=v;}
      }
      t.dispatchEvent(new Event('input',{bubbles:true}));t.dispatchEvent(new Event('change',{bubbles:true}));
      if(go){
       var k={key:'Enter',code:'Enter',bubbles:true,cancelable:true};
       var ok=t.dispatchEvent(new KeyboardEvent('keydown',k));
       t.dispatchEvent(new KeyboardEvent('keyup',k));
       if(ok&&t.form){if(t.form.requestSubmit){t.form.requestSubmit();}else{t.form.submit();}}
      }
     }
    };window.open=function(u){if(u)location.href=u;return null;};}

    """
}
