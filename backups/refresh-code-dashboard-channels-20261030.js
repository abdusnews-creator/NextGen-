// NextGen refresh code backup — saved before removal on 2026-10-30
// These scripts were removed from dashboard.html and channels.html as requested.

/* BACKUP FROM dashboard.html */
<script id="channels-pull-to-refresh">
(function(){
  var main=document.querySelector('.app main');
  var refreshButton=document.querySelector('.refresh-page');
  if(!main)return;
  function forceRefresh(){
    var url=new URL(window.location.href);
    url.searchParams.set('ng_refresh',String(Date.now()));
    url.searchParams.set('ng_v','30');
    window.location.replace(url.toString());
  }
  if(refreshButton){
    refreshButton.addEventListener('click',function(e){
      e.preventDefault();
      forceRefresh();
    });
  }
  var startY=0,startX=0,tracking=false,dragging=false,refreshed=false;
  var threshold=60,indicator=document.createElement('div');
  indicator.setAttribute('role','status');
  indicator.setAttribute('aria-live','polite');
  indicator.textContent='Pull to refresh';
  indicator.style.cssText='position:fixed;z-index:9999;top:58px;left:50%;transform:translateX(-50%);padding:8px 14px;border:1px solid #1e4fb5;border-radius:20px;background:#07123a;color:#fff;font:600 12px/1.2 system-ui,sans-serif;box-shadow:0 4px 16px #0006;opacity:0;transition:opacity .12s;pointer-events:none;white-space:nowrap';
  document.body.appendChild(indicator);
  function show(label){indicator.textContent=label;indicator.style.opacity='1';}
  function hide(){indicator.style.opacity='0';}
  function touchPoint(list){return list&&list.length?list[0]:null;}
  document.addEventListener('touchstart',function(e){
    var t=touchPoint(e.touches);
    if(!t||e.touches.length!==1)return;
    if(e.target&&e.target.closest&&e.target.closest('button,a,input,textarea,select'))return;
    startY=t.clientY;startX=t.clientX;
    tracking=main.scrollTop<=2;
    dragging=false;refreshed=false;
    if(tracking)indicator.textContent='Pull to refresh';
  },{passive:true,capture:true});
  document.addEventListener('touchmove',function(e){
    if(!tracking||refreshed)return;
    var t=touchPoint(e.touches);
    if(!t){tracking=false;hide();return;}
    var dy=t.clientY-startY,dx=t.clientX-startX;
    if(Math.abs(dx)>Math.abs(dy)*0.8){tracking=false;hide();return;}
    if(dy>6&&main.scrollTop<=2){
      dragging=true;
      show(dy>=threshold?'Release to refresh':'Pull to refresh');
      if(e.cancelable)e.preventDefault();
    }else if(dy<0){tracking=false;dragging=false;hide();}
  },{passive:false,capture:true});
  document.addEventListener('touchend',function(e){
    if(!tracking||refreshed){hide();tracking=false;return;}
    var t=touchPoint(e.changedTouches);
    var dy=t?t.clientY-startY:0,dx=t?t.clientX-startX:0;
    tracking=false;
    if(dragging&&dy>=threshold&&Math.abs(dx)<Math.abs(dy)*0.8&&main.scrollTop<=2){
      refreshed=true;show('Refreshing…');forceRefresh();return;
    }
    hide();dragging=false;
  },{passive:true,capture:true});
  document.addEventListener('touchcancel',function(){tracking=false;dragging=false;hide();},{passive:true});
})();
</script>

/* BACKUP FROM channels.html */
<script id="channels-pull-to-refresh">
(function(){
  var main=document.querySelector('.app main');
  var refreshButton=document.querySelector('.refresh-page');
  if(!main)return;
  function forceRefresh(){
    var url=new URL(window.location.href);
    url.searchParams.set('ng_refresh',String(Date.now()));
    url.searchParams.set('ng_v','30');
    window.location.replace(url.toString());
  }
  if(refreshButton){
    refreshButton.addEventListener('click',function(e){
      e.preventDefault();
      forceRefresh();
    });
  }
  var startY=0,startX=0,tracking=false,dragging=false,refreshed=false;
  var threshold=60,indicator=document.createElement('div');
  indicator.setAttribute('role','status');
  indicator.setAttribute('aria-live','polite');
  indicator.textContent='Pull to refresh';
  indicator.style.cssText='position:fixed;z-index:9999;top:58px;left:50%;transform:translateX(-50%);padding:8px 14px;border:1px solid #1e4fb5;border-radius:20px;background:#07123a;color:#fff;font:600 12px/1.2 system-ui,sans-serif;box-shadow:0 4px 16px #0006;opacity:0;transition:opacity .12s;pointer-events:none;white-space:nowrap';
  document.body.appendChild(indicator);
  function show(label){indicator.textContent=label;indicator.style.opacity='1';}
  function hide(){indicator.style.opacity='0';}
  function touchPoint(list){return list&&list.length?list[0]:null;}
  document.addEventListener('touchstart',function(e){
    var t=touchPoint(e.touches);
    if(!t||e.touches.length!==1)return;
    if(e.target&&e.target.closest&&e.target.closest('button,a,input,textarea,select'))return;
    startY=t.clientY;startX=t.clientX;
    tracking=main.scrollTop<=2;
    dragging=false;refreshed=false;
    if(tracking)indicator.textContent='Pull to refresh';
  },{passive:true,capture:true});
  document.addEventListener('touchmove',function(e){
    if(!tracking||refreshed)return;
    var t=touchPoint(e.touches);
    if(!t){tracking=false;hide();return;}
    var dy=t.clientY-startY,dx=t.clientX-startX;
    if(Math.abs(dx)>Math.abs(dy)*0.8){tracking=false;hide();return;}
    if(dy>6&&main.scrollTop<=2){
      dragging=true;
      show(dy>=threshold?'Release to refresh':'Pull to refresh');
      if(e.cancelable)e.preventDefault();
    }else if(dy<0){tracking=false;dragging=false;hide();}
  },{passive:false,capture:true});
  document.addEventListener('touchend',function(e){
    if(!tracking||refreshed){hide();tracking=false;return;}
    var t=touchPoint(e.changedTouches);
    var dy=t?t.clientY-startY:0,dx=t?t.clientX-startX:0;
    tracking=false;
    if(dragging&&dy>=threshold&&Math.abs(dx)<Math.abs(dy)*0.8&&main.scrollTop<=2){
      refreshed=true;show('Refreshing…');forceRefresh();return;
    }
    hide();dragging=false;
  },{passive:true,capture:true});
  document.addEventListener('touchcancel',function(){tracking=false;dragging=false;hide();},{passive:true});
})();
</script>
