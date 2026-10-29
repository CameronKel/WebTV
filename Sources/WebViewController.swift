import UIKit

/// Full-screen web page driven like a normal TV app:
///   D-pad / swipe   -> move a highlight between links and buttons
///   Select (click)  -> activate the highlighted item
///   Play/Pause      -> play/pause the page's video, or go home if there isn't one
///   Menu / Back     -> browser back (exits the app when there's no history)
final class WebViewController: UIViewController {
    private var web: LegacyWebView?
    private let messageLabel = UILabel()
    private var swipeAccumulated = CGPoint.zero
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

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(pan)

        web.load(Config.homeURL)
    }

    // MARK: - Page actions

    @discardableResult
    private func runPage(_ call: String) -> String {
        web?.evaluate(PageScript.prelude + call) ?? ""
    }

    private func move(_ direction: String) {
        runPage("window.__atv.move('\(direction)')")
    }

    private func activate() {
        let result = runPage("window.__atv.activate()")
        if let data = result.data(using: .utf8),
           let field = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            promptForText(field)
        }
    }

    /// Swipes on the touch surface step the highlight, like the tvOS focus engine.
    @objc private func handleSwipe(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began { swipeAccumulated = .zero }
        let t = pan.translation(in: view)
        pan.setTranslation(.zero, in: view)
        swipeAccumulated.x += t.x
        swipeAccumulated.y += t.y

        let step = Config.swipeStep
        if abs(swipeAccumulated.x) >= step, abs(swipeAccumulated.x) > abs(swipeAccumulated.y) {
            move(swipeAccumulated.x > 0 ? "right" : "left")
            swipeAccumulated = .zero
        } else if abs(swipeAccumulated.y) >= step {
            move(swipeAccumulated.y > 0 ? "down" : "up")
            swipeAccumulated = .zero
        }
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
            self?.runPage("window.__atv.setText.apply(window.__atv,\(argsJS))")
        }
        alert.addAction(UIAlertAction(title: "Done & Go", style: .default) { _ in submit(true) })
        alert.addAction(UIAlertAction(title: "Done", style: .default) { _ in submit(false) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Remote buttons

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passOn = Set<UIPress>()
        for press in presses {
            switch press.type {
            case .select: activate()
            case .upArrow: move("up")
            case .downArrow: move("down")
            case .leftArrow: move("left")
            case .rightArrow: move("right")
            case .pageUp: runPage("window.__atv.scrollPage('up',0.9)")
            case .pageDown: runPage("window.__atv.scrollPage('down',0.9)")
            case .playPause:
                if runPage("window.__atv.playPause()").isEmpty { web?.load(Config.homeURL) }
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

/// JavaScript injected into whatever page is loaded. It keeps track of the
/// highlighted element, draws a ring around it, and picks the next element
/// in a given direction by on-screen geometry.
private enum PageScript {
    static let prelude = """
    if(!window.__atv){window.__atv={
     sel:'a[href],button,input,select,textarea,summary,video,[role=button],[role=link],[role=tab],[role=menuitem],[role=option],[onclick],[tabindex]:not([tabindex="-1"])',
     items:function(){
      var out=[],seen={},els=document.querySelectorAll(this.sel);
      for(var i=0;i<els.length;i++){
       var e=els[i];if(e.disabled||e.closest('[aria-hidden=true]'))continue;
       var r=e.getBoundingClientRect();if(r.width<4||r.height<4)continue;
       var s=getComputedStyle(e);if(s.visibility==='hidden'||s.opacity==='0')continue;
       var k=Math.round(r.left)+','+Math.round(r.top)+','+Math.round(r.width)+','+Math.round(r.height);
       if(seen[k])continue;seen[k]=1;out.push({e:e,r:r});
      }
      return out;
     },
     move:function(dir){
      var list=this.items(),cur=this.cur,vh=window.innerHeight,cr=null;
      if(cur&&document.contains(cur)){cr=cur.getBoundingClientRect();if(cr.bottom<0||cr.top>vh)cr=null;}
      if(!cr){
       var first=null;
       for(var i=0;i<list.length;i++){var c=list[i];
        if(c.r.bottom>0&&c.r.top<vh&&(!first||c.r.top<first.r.top-4||(Math.abs(c.r.top-first.r.top)<=4&&c.r.left<first.r.left)))first=c;}
       if(first)this.focus(first.e);else this.scrollPage(dir);
       return;
      }
      var cx=(cr.left+cr.right)/2,cy=(cr.top+cr.bottom)/2,best=null,bestScore=1e9,h=dir==='left'||dir==='right';
      for(var i=0;i<list.length;i++){
       var c=list[i],r=c.r;if(c.e===cur||cur.contains(c.e)||c.e.contains(cur))continue;
       var x=(r.left+r.right)/2,y=(r.top+r.bottom)/2,main,side;
       if(dir==='right'){if(x-cx<10||r.left<=cr.left)continue;main=Math.max(0,r.left-cr.right);}
       else if(dir==='left'){if(cx-x<10||r.right>=cr.right)continue;main=Math.max(0,cr.left-r.right);}
       else if(dir==='down'){if(y-cy<10||r.top<=cr.top)continue;main=Math.max(0,r.top-cr.bottom);}
       else{if(cy-y<10||r.bottom>=cr.bottom)continue;main=Math.max(0,cr.top-r.bottom);}
       if(h){side=(r.top<cr.bottom&&r.bottom>cr.top)?0:Math.abs(y-cy);}
       else{side=(r.left<cr.right&&r.right>cr.left)?0:Math.abs(x-cx);}
       var score=main+side*3;if(score<bestScore){bestScore=score;best=c;}
      }
      if(best)this.focus(best.e);else this.scrollPage(dir);
     },
     focus:function(e){
      this.cur=e;
      var r=e.getBoundingClientRect(),vh=window.innerHeight,vw=window.innerWidth;
      if(r.top<60||r.bottom>vh-60||r.left<0||r.right>vw){
       try{e.scrollIntoView({block:'center',inline:'nearest'});}catch(_){e.scrollIntoView();}
      }
      var o={bubbles:true,view:window};
      e.dispatchEvent(new MouseEvent('mouseover',o));e.dispatchEvent(new MouseEvent('mouseenter',{view:window}));
      try{e.focus({preventScroll:true});}catch(_){}
      this.ring();
     },
     ring:function(){
      var d=this.box;
      if(!d||!document.body.contains(d)){
       d=this.box=document.createElement('div');
       d.style.cssText='position:fixed;pointer-events:none;z-index:2147483647;box-sizing:border-box;border:4px solid #fff;border-radius:10px;box-shadow:0 0 0 3px rgba(0,0,0,.6),0 0 28px rgba(255,255,255,.55);transition:all .12s ease-out';
       document.body.appendChild(d);
      }
      var e=this.cur;if(!e||!document.contains(e)){d.style.display='none';return;}
      var r=e.getBoundingClientRect();
      d.style.display='block';d.style.left=(r.left-6)+'px';d.style.top=(r.top-6)+'px';
      d.style.width=(r.width+12)+'px';d.style.height=(r.height+12)+'px';
     },
     activate:function(){
      var e=this.cur;if(!e||!document.contains(e))return '';
      var r=e.getBoundingClientRect(),cx=(r.left+r.right)/2,cy=(r.top+r.bottom)/2;
      var t=e.closest('textarea,input,[contenteditable]');
      if(t&&!t.disabled&&!t.readOnly&&(t.tagName==='TEXTAREA'||t.isContentEditable||
         (t.tagName==='INPUT'&&/^(text|search|email|url|password|number|tel)$/.test(t.type)))){
       this.field=t;t.focus();
       return JSON.stringify({secure:t.type==='password',value:t.isContentEditable?t.innerText:t.value,
        label:t.getAttribute('aria-label')||t.placeholder||t.name||''});
      }
      if(e.tagName==='VIDEO'){this.playPause(e);return '';}
      var a=e.closest('a[target]');if(a)a.target='_self';
      var o={bubbles:true,cancelable:true,view:window,clientX:cx,clientY:cy};
      function fire(n,C){if(C)e.dispatchEvent(new C(n,o));}
      fire('pointerdown',window.PointerEvent);fire('mousedown',MouseEvent);
      fire('pointerup',window.PointerEvent);fire('mouseup',MouseEvent);fire('click',MouseEvent);
      var self=this;setTimeout(function(){self.ring();},300);
      return '';
     },
     playPause:function(v){
      v=v||document.querySelector('video');if(!v)return '';
      if(v.paused){v.play();}else{v.pause();}
      return 'ok';
     },
     scrollPage:function(dir,f){
      f=f||0.6;var dx=0,dy=0;
      if(dir==='up')dy=-window.innerHeight*f;else if(dir==='down')dy=window.innerHeight*f;
      else if(dir==='left')dx=-window.innerWidth*f;else dx=window.innerWidth*f;
      for(var e=document.elementFromPoint(window.innerWidth/2,window.innerHeight/2);e&&e!==document.body&&e!==document.documentElement;e=e.parentElement){
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
    };
    window.addEventListener('scroll',function(){window.__atv.ring();},true);
    window.addEventListener('resize',function(){window.__atv.ring();});
    window.open=function(u){if(u)location.href=u;return null;};}

    """
}
