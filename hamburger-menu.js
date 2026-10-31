(function(){
  "use strict";
  function init(){
    if(document.getElementById("ng-menu-drawer")) return;
    fetch("./hamburger-menu.html",{cache:"no-store"})
      .then(function(r){if(!r.ok)throw new Error("Menu component unavailable");return r.text();})
      .then(function(html){
        var holder=document.createElement("div");
        holder.id="ng-shared-hamburger-root";
        holder.innerHTML=html;
        document.body.appendChild(holder);
        bind();
      })
      .catch(function(err){console.error("NextGen navigation menu:",err);});
  }
  function bind(){
    var trigger=document.getElementById("ng-hamburger");
    var drawer=document.getElementById("ng-menu-drawer");
    var backdrop=document.getElementById("ng-menu-backdrop");
    var close=document.getElementById("ng-menu-close");
    if(!trigger||!drawer||!backdrop||!close||drawer.dataset.sharedReady==="1")return;
    drawer.dataset.sharedReady="1";
    function openMenu(){
      drawer.classList.add("is-open");
      drawer.setAttribute("aria-hidden","false");
      backdrop.hidden=false;
      trigger.setAttribute("aria-expanded","true");
      trigger.setAttribute("aria-label","Close navigation menu");
      document.body.classList.add("ng-menu-open");
    }
    function closeMenu(){
      drawer.classList.remove("is-open");
      drawer.setAttribute("aria-hidden","true");
      backdrop.hidden=true;
      trigger.setAttribute("aria-expanded","false");
      trigger.setAttribute("aria-label","Open navigation menu");
      document.body.classList.remove("ng-menu-open");
    }
    trigger.addEventListener("click",function(){drawer.classList.contains("is-open")?closeMenu():openMenu();});
    close.addEventListener("click",closeMenu);
    backdrop.addEventListener("click",closeMenu);
    document.addEventListener("keydown",function(e){if(e.key==="Escape"&&drawer.classList.contains("is-open"))closeMenu();});
    drawer.querySelectorAll(".ng-menu-accordion-trigger").forEach(function(btn){
      btn.addEventListener("click",function(){
        var panel=btn.nextElementSibling;
        if(!panel)return;
        var expanded=btn.getAttribute("aria-expanded")==="true";
        btn.setAttribute("aria-expanded",String(!expanded));
        panel.hidden=expanded;
        var chevron=btn.querySelector("i");
        if(chevron)chevron.textContent=expanded?"⌄":"⌃";
      });
    });
    var seeLess=document.getElementById("ng-menu-see-less");
    var mainLinks=drawer.querySelector(".ng-menu-main-links");
    if(seeLess&&mainLinks){
      seeLess.addEventListener("click",function(){
        var collapsed=mainLinks.classList.toggle("is-collapsed");
        seeLess.textContent=collapsed?"See more":"See less";
      });
    }
    drawer.querySelectorAll("a[href]").forEach(function(link){
      link.addEventListener("click",function(){if(link.getAttribute("href")!=="#")closeMenu();});
    });
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init,{once:true});
  else init();
})();