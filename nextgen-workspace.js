(function(){
  'use strict';
  if (!window.supabase || !window.NEXTGEN_SUPABASE_CONFIG) return;
  const client = window.supabase.createClient(window.NEXTGEN_SUPABASE_CONFIG.url, window.NEXTGEN_SUPABASE_CONFIG.anonKey);
  const $ = id => document.getElementById(id);
  const main = document.querySelector('.app main');
  const page = (location.pathname.split('/').pop() || 'index.html').toLowerCase();
  let user = null;
  let channels = [];
  let content = [];
  let settings = null;
  let authPanel, authMessage;
  function showAuthPanel(){
    const drawer=document.getElementById('ng-menu-drawer');
    if(!drawer)return;
    if(authPanel)authPanel.remove();
    authPanel=document.createElement('div');
    authPanel.id='ng-workspace-auth';
    authPanel.style.cssText='margin:14px 0 4px;padding:12px;border:1px solid #285a89;border-radius:11px;background:#07142d;color:#eef5ff';
    const title=document.createElement('strong');title.textContent='NextGen Account';title.style.cssText='display:block;margin-bottom:8px;color:#fff;font-size:14px';
    authMessage=document.createElement('p');authMessage.className='muted';authMessage.style.cssText='font-size:12px;line-height:1.45;margin:0 0 8px;color:#a8c1e8';
    const input=document.createElement('input');input.type='email';input.autocomplete='email';input.placeholder='Your email address';input.required=true;input.id='ng-workspace-email';input.style.cssText='box-sizing:border-box;width:100%;min-height:40px;margin:0 0 8px;padding:9px;border:1px solid #285a89;border-radius:8px;background:#061a35;color:#fff';
    const button=document.createElement('button');button.type='button';button.textContent='Sign in';button.style.cssText='width:100%;min-height:40px;padding:8px 12px;border:1px solid #21bdf1;border-radius:9px;background:#0c3154;color:#fff;font-weight:700';
    button.addEventListener('click',async function(){
      const email=input.value.trim();
      if(!email){authMessage.textContent='Enter your email address first.';return;}
      button.disabled=true;authMessage.textContent='Sending secure sign-in link…';
      const {error}=await client.auth.signInWithOtp({email,options:{emailRedirectTo:location.origin+location.pathname}});
      button.disabled=false;
      authMessage.textContent=error?'Sign-in link could not be sent: '+error.message:'Check your email and open the secure NextGen sign-in link on this device.';
    });
    authPanel.append(title,authMessage,input,button);
    const old=drawer.querySelector('.ng-menu-logout');
    if(old)old.remove();
    drawer.append(authPanel);
  }
  function setSignedIn(){
    if(!authPanel)return;
    authPanel.innerHTML='';
    const title=document.createElement('strong');title.textContent='NextGen Account';title.style.cssText='display:block;margin-bottom:6px;color:#fff;font-size:14px';
    const info=document.createElement('p');info.className='muted';info.textContent='Signed in as '+(user.email||'authenticated user');info.style.cssText='font-size:12px;line-height:1.45;margin:0 0 9px;color:#a8c1e8;overflow-wrap:anywhere';
    const button=document.createElement('button');button.type='button';button.textContent='Sign out';button.style.cssText='width:100%;min-height:40px;padding:8px 12px;border:1px solid #285a89;border-radius:9px;background:#10213d;color:#fff;font-weight:700';
    button.addEventListener('click',async()=>{button.disabled=true;const {error}=await client.auth.signOut();if(error){button.disabled=false;info.textContent='Could not sign out: '+error.message;}});
    authPanel.append(title,info,button);
  }
  async function requireUser(){
    if(!user)throw new Error('Open the three-line menu and sign in at the bottom to continue.');
    return user;
  }
  async function loadBase(){
    await requireUser();
    const [c,items,s]=await Promise.all([
      client.from('channels').select('id,platform,display_name,handle,connection_status,is_paused').order('created_at',{ascending:false}),
      client.from('content_items').select('id,channel_id,platform,content_type,title,caption,hashtags,tags,keywords,thumbnail_url,thumbnail_prompt,status,scheduled_for,created_at').order('created_at',{ascending:false}).limit(100),
      client.from('automation_settings').select('*').eq('owner_id',user.id).maybeSingle()
    ]);
    if(c.error)throw c.error;if(items.error)throw items.error;if(s.error)throw s.error;
    channels=c.data||[];content=items.data||[];settings=s.data||null;
  }
  function parseList(v){return String(v||'').split(/[,;\n]/).map(x=>x.trim().replace(/^#/,'')).filter(Boolean);}
  function safeText(node,value){if(node)node.textContent=value==null?'':String(value);}
  function empty(root,message){if(root){root.innerHTML='';const p=document.createElement('p');p.className='muted';p.textContent=message;root.append(p);}}
  function addEntry(root,title,meta,description,actions){
    const el=document.createElement('div');el.className='ng-entry';
    const t=document.createElement('strong');t.textContent=title||'Untitled';
    const m=document.createElement('small');m.textContent=meta||'';
    const p=document.createElement('p');p.textContent=description||'';
    el.append(t,m,p);
    (actions||[]).forEach(a=>{const b=document.createElement('button');b.type='button';b.textContent=a.label;b.addEventListener('click',a.onClick);el.append(b);});
    root.append(el);
  }
  async function saveDraft(form){
    const platform=($('draftPlatform')&&$('draftPlatform').value)||'youtube';
    const typeMap={'Reels / Short Video':'reel','Long-form Video':'long_form_video','Photo Post':'photo_post','Carousel Photo Post':'carousel_photo_post','Story':'story','Text Post':'text_post'};
    const row={
      owner_id:user.id,platform,content_type:typeMap[$('draftType').value]||'reel',
      title:$('draftTitle').value.trim(),caption:$('draftCaption').value.trim(),
      thumbnail_url:$('draftImage').value.trim()||null,thumbnail_prompt:$('draftPrompt').value.trim()||null,
      hashtags:parseList($('draftHash').value),tags:parseList($('draftTags').value),keywords:parseList($('draftTags').value),
      status:'draft',safety_checks:{manual_review_required:true,checks_completed:false,published:false,scheduled:false}
    };
    const {error}=await client.from('content_items').insert(row);
    if(error)throw error;
    form.reset();setNote('draftNote','Draft saved to your NextGen account. It is unpublished and awaits your review.',false);
    await loadBase();renderContent();
  }
  function renderChannels(){
    const root=document.querySelector('.app main .list');if(!root)return;
    // Preserve the four approved starter cards. Overlay saved records on their
    // matching platform cards and append additional channels without duplicates.
    const platformClass={youtube:'yt',facebook:'fb',instagram:'ig',threads:'th'};
    const platformIcon={youtube:'▶',facebook:'f',instagram:'◎',threads:'＠'};
    const starterByPlatform={};
    root.querySelectorAll('.card').forEach(card=>{
      const key=Object.keys(platformClass).find(p=>card.classList.contains(platformClass[p]));
      if(key&&!starterByPlatform[key])starterByPlatform[key]=card;
    });
    if(!channels.length){
      if(!root.querySelector('.card'))empty(root,'No channels are saved in this workspace yet. Use Add Channel to verify and save a profile.');
      return;
    }
    const usedStarter=new Set();
    channels.forEach(ch=>{
      const platform=String(ch.platform||'').toLowerCase();
      const existing=starterByPlatform[platform]&&!usedStarter.has(platform)?starterByPlatform[platform]:null;
      const card=existing||document.createElement('div');
      if(existing)usedStarter.add(platform);
      else card.className='card '+(platformClass[platform]||'');
      if(!existing){
        const icon=document.createElement('div');icon.className='ico';icon.textContent=platformIcon[platform]||'•';
        const info=document.createElement('div');info.className='info';
        const name=document.createElement('b');const handle=document.createElement('span');
        info.append(name,handle);
        const status=document.createElement('div');status.className='st';
        card.append(icon,info,status);root.append(card);
      }
      const nameNode=card.querySelector('.info b');
      const handleNode=card.querySelector('.info span');
      const statusNode=card.querySelector('.st');
      if(nameNode)nameNode.textContent=ch.display_name||platform||'Channel';
      if(handleNode)handleNode.textContent=ch.handle?'@'+String(ch.handle).replace(/^@/,''):'Profile name pending';
      if(statusNode)statusNode.textContent='Connection: '+(ch.connection_status||'pending')+(ch.is_paused?' · Paused':'');
    });
  }
  function renderContent(){
    const root=$('draftList');if(!root)return;
    root.innerHTML='';safeText($('draftCount'),content.length);
    if(!content.length){empty(root,'No drafts saved in this account yet.');return;}
    content.forEach(item=>addEntry(root,item.title,item.content_type+' · '+item.platform+' · '+item.status,item.caption,[
      {label:'Copy SEO',onClick:()=>navigator.clipboard?.writeText([item.title,item.caption,(item.hashtags||[]).map(x=>'#'+x).join(' '),(item.tags||[]).join(', ')].filter(Boolean).join('\n'))},
      ...(item.status==='draft'||item.status==='pending_approval'?[{label:'Delete',onClick:async()=>{if(!confirm('Delete this draft?'))return;const {error}=await client.from('content_items').delete().eq('id',item.id);if(error){setNote('draftNote',error.message,true);return;}await loadBase();renderContent();}}]:[])
    ]));
  }
  async function setApprovalMode(mode){
    const enabled=mode==='auto';
    const {error}=await client.from('automation_settings').upsert({
      owner_id:user.id,approval_mode:mode,auto_approval_enabled:enabled,background_mode_enabled:false,
      timezone:'Asia/Kolkata',daily_idea_times:(settings&&settings.daily_idea_times)||['08:00:00','14:00:00','18:00:00']
    },{onConflict:'owner_id'});
    if(error)throw error;
    settings=Object.assign({},settings||{},{approval_mode:mode,auto_approval_enabled:enabled,background_mode_enabled:false});
    if($('manualMode'))$('manualMode').classList.toggle('selected',!enabled);
    if($('autoMode'))$('autoMode').classList.toggle('selected',enabled);
    if($('modeNote'))$('modeNote').textContent=enabled?'Auto mode preference saved. No automatic approval or publishing worker is active; every post still needs an explicit approval action.':'Manual Approval is active. Every post requires your explicit approval.';
    if($('manual-approval-mode'))$('manual-approval-mode').setAttribute('aria-pressed',String(!enabled));
    if($('auto-approval-mode'))$('auto-approval-mode').setAttribute('aria-pressed',String(enabled));
    if($('publishing-mode-label'))$('publishing-mode-label').textContent=enabled?'Auto Approval Mode — ON':'Manual Approval Mode — ON';
    if($('auto-approval-label'))$('auto-approval-label').textContent=enabled?'ON':'OFF';
    if($('approval-mode-note'))$('approval-mode-note').textContent=enabled?'Auto mode preference saved only. No automatic approval or publishing worker is active.':'Manual Approval is active. Every post requires your explicit approval.';
    if($('dash1-publishing-status'))$('dash1-publishing-status').textContent=enabled?'Auto Approval preference — ON (no auto-publisher active)':'Manual Approval Mode — ON';
    if($('dash1-manual-approval'))$('dash1-manual-approval').classList.toggle('is-selected',!enabled);
    if($('dash1-auto-approval'))$('dash1-auto-approval').classList.toggle('is-selected',enabled);
  }
  function renderApprovals(){
    const root=$('approvalList');if(!root)return;
    root.innerHTML='';
    const pending=content.filter(x=>['draft','pending_approval'].includes(x.status));
    if(!pending.length){empty(root,'No drafts awaiting review.');return;}
    pending.forEach(item=>addEntry(root,item.title,item.platform+' · '+item.content_type+' · '+item.status,item.caption,[
      {label:'Approve',onClick:async()=>{const {error}=await client.rpc('review_content_item',{p_content_id:item.id,p_action:'approved',p_note:null});if(error){setNote('modeNote',error.message,true);return;}await loadBase();renderApprovals();}},
      {label:'Reject',onClick:async()=>{const note=prompt('Optional reason for rejection:')||'';const {error}=await client.rpc('review_content_item',{p_content_id:item.id,p_action:'rejected',p_note:note});if(error){setNote('modeNote',error.message,true);return;}await loadBase();renderApprovals();}}
    ]));
  }
  function fillSelect(select,items,placeholder,labelFn){
    if(!select)return;select.innerHTML='';
    const first=document.createElement('option');first.value='';first.textContent=placeholder;select.append(first);
    items.forEach(x=>{const o=document.createElement('option');o.value=x.id;o.textContent=labelFn(x);select.append(o);});
  }
  async function saveDailyTimes(){
    const times=[$('slotMorning').value,$('slotAfternoon').value,$('slotEvening').value].filter(Boolean);
    const {error}=await client.from('automation_settings').upsert({owner_id:user.id,approval_mode:(settings&&settings.approval_mode)||'manual',auto_approval_enabled:!!(settings&&settings.auto_approval_enabled),background_mode_enabled:false,timezone:'Asia/Kolkata',daily_idea_times:times},{onConflict:'owner_id'});
    if(error)throw error;
    setNote('slotNote','Daily plan times saved to your NextGen account. These are planning reminders only.',false);
    await loadBase();
  }
  async function scheduleContent(){
    const contentId=$('scheduleContent').value,channelId=$('scheduleChannel').value;
    const date=$('scheduleDate').value,time=$('scheduleTime').value;
    if(!contentId||!channelId||!date||!time)throw new Error('Choose approved content, a channel, date and time.');
    const scheduled=new Date(date+'T'+time+':00');
    if(Number.isNaN(scheduled.getTime())||scheduled<=new Date())throw new Error('Choose a future date and time.');
    const {error}=await client.rpc('schedule_approved_content',{p_content_id:contentId,p_channel_id:channelId,p_scheduled_for:scheduled.toISOString()});
    if(error)throw error;
    setNote('scheduleNote','Added to the NextGen queue. No post was sent to a social platform.',false);
    $('scheduleForm').reset();$('scheduleTime').value='08:00';await loadBase();renderSchedule();
  }
  async function renderSchedule(){
    fillSelect($('scheduleContent'),content.filter(x=>x.status==='approved'),'Choose an approved draft',x=>x.title+' · '+x.platform);
    fillSelect($('scheduleChannel'),channels.filter(x=>!x.is_paused),'Choose an active channel',x=>x.display_name+' · '+x.platform);
    const root=$('scheduleList');if(!root)return;
    root.innerHTML='';
    const {data:jobs,error}=await client.from('publishing_jobs').select('id,content_id,channel_id,scheduled_for,status').order('scheduled_for',{ascending:true}).limit(100);
    if(error)throw error;
    if(!jobs||!jobs.length){empty(root,'No scheduled jobs in your account yet.');return;}
    jobs.forEach(job=>{
      const item=content.find(x=>x.id===job.content_id),channel=channels.find(x=>x.id===job.channel_id);
      addEntry(root,item?item.title:'Scheduled content', (channel?channel.display_name:'Channel')+' · '+new Date(job.scheduled_for).toLocaleString()+' · '+job.status,'Queued in NextGen. Publishing has not been performed.',[
        ...(job.status==='queued'?[{label:'Cancel',onClick:async()=>{const {error}=await client.from('publishing_jobs').update({status:'cancelled',updated_at:new Date().toISOString()}).eq('id',job.id);if(error){setNote('scheduleNote',error.message,true);return;}await loadBase();renderSchedule();}}]:[])
      ]);
    });
  }
  function periodDays(){
    const v=$('analyticsPeriod')?.value||'Last 28 days';
    return v.includes('7')?7:v.includes('90')?90:28;
  }
  async function loadAnalytics(){
    const start=new Date();start.setDate(start.getDate()-periodDays()+1);const from=start.toISOString().slice(0,10);
    const {data,error}=await client.from('channel_analytics_daily').select('channel_id,metric_date,views,followers,followers_gained,likes,comments,shares,watch_time_seconds,engagement_rate,source').gte('metric_date',from).order('metric_date',{ascending:false});
    if(error)throw error;
    const rows=data||[];
    const totals=rows.reduce((a,r)=>{a.views+=Number(r.views||0);a.likes+=Number(r.likes||0);a.comments+=Number(r.comments||0);a.shares+=Number(r.shares||0);a.watch+=Number(r.watch_time_seconds||0);return a;},{views:0,likes:0,comments:0,shares:0,watch:0});
    const latestByChannel={};rows.forEach(r=>{if(!latestByChannel[r.channel_id])latestByChannel[r.channel_id]=Number(r.followers||0);});
    const followers=Object.values(latestByChannel).reduce((a,b)=>a+b,0);
    const engagement=totals.views?((totals.likes+totals.comments+totals.shares)/totals.views*100):null;
    const metricNodes=document.querySelectorAll('.ng-metric-grid article strong');
    if(metricNodes.length>=4){
      metricNodes[0].textContent=rows.length?totals.views.toLocaleString():'—';
      metricNodes[1].textContent=rows.length?followers.toLocaleString():'—';
      metricNodes[2].textContent=engagement===null?'—':engagement.toFixed(2)+'%';
      metricNodes[3].textContent=rows.length?(totals.watch/3600).toFixed(1)+' h':'—';
    }
    const status=$('ng-analytics-status')||document.querySelector('.ng-analytics-status');
    if(status)status.textContent=rows.length?'Metrics loaded from verified daily analytics records.':'No verified analytics have been synced from the platforms yet.';
    const platformRows=document.querySelectorAll('.ng-platform-row');
    const names=['youtube','facebook','instagram','threads'];
    platformRows.forEach((node,i)=>{
      const matching=channels.filter(c=>c.platform===names[i]);
      const label=node.querySelector('span');
      if(label)label.textContent=matching.length?matching.length+' channel(s) · '+matching.map(c=>c.connection_status).join(', '):'No connected channel record';
    });
  }
  async function renderDashboard(){
    const metric=document.querySelectorAll('.dash1-analytics-grid .dash1-metric strong');
    const {data:analytics,error}=await client.from('channel_analytics_daily').select('views,watch_time_seconds,followers,metric_date,channel_id').order('metric_date',{ascending:false}).limit(1000);
    if(error)throw error;
    const rows=analytics||[];
    const views=rows.reduce((a,r)=>a+Number(r.views||0),0),watch=rows.reduce((a,r)=>a+Number(r.watch_time_seconds||0),0);
    const latest={};rows.forEach(r=>{if(!latest[r.channel_id])latest[r.channel_id]=Number(r.followers||0);});
    if(metric.length>=4){metric[0].textContent=rows.length?views.toLocaleString():'—';metric[1].textContent=rows.length?(watch/3600).toFixed(1):'—';metric[2].textContent=rows.length?Object.values(latest).reduce((a,b)=>a+b,0).toLocaleString():'—';metric[3].textContent='—';}
    const notice=document.querySelector('.dash1-analytics-notice');if(notice)notice.textContent=rows.length?'Verified analytics records loaded. Revenue is not available in the current integration.':'No verified analytics have been synced yet. Figures remain blank rather than showing estimates.';
    const recent=document.querySelector('.dash1-content-list');
    if(recent){recent.innerHTML='';const items=content.slice(0,5);if(!items.length)empty(recent,'No content saved in your workspace yet.');else items.forEach(x=>{const article=document.createElement('article');article.className='dash1-content-row';const info=document.createElement('div');info.className='dash1-content-info';const h=document.createElement('h3');h.textContent=x.title||'Untitled';const p=document.createElement('p');p.textContent=x.platform+' · '+x.status;info.append(h,p);article.append(info);recent.append(article);});}
    const channelRows=document.querySelectorAll('.dash1-channel-overview .dash1-overview-row');
    channelRows.forEach((node,i)=>{const label=node.querySelector('span:nth-child(2)');const status=node.querySelector('.dash1-planned');const name=['youtube','facebook','instagram','threads'][i];const group=channels.filter(c=>c.platform===name);if(label)label.textContent=name[0].toUpperCase()+name.slice(1);if(status)status.textContent=group.length?group.length+' · '+group[0].connection_status:'Not connected';});
    const pending=content.filter(x=>['draft','pending_approval'].includes(x.status)).length;
    const pendingCard=document.querySelector('.dash1-recent-head');if(pendingCard)pendingCard.setAttribute('data-pending-count',String(pending));
    const mode=settings&&settings.approval_mode==='auto'?'auto':'manual';
    if($('dash1-publishing-status'))$('dash1-publishing-status').textContent=mode==='auto'?'Auto Approval preference — ON (no auto-publisher active)':'Manual Approval Mode — ON';
  }
  async function renderSettings(){
    const {data:connections,error}=await client.from('platform_connections').select('platform,connection_status,display_name,handle,last_error').order('platform');
    if(error)throw error;
    const panel=$('integrations');if(panel){const rows=panel.querySelectorAll('.ng-settings-line');const names=['youtube','facebook','instagram','threads'];rows.forEach((row,i)=>{const match=(connections||[]).find(x=>x.platform===names[i]);const span=row.querySelector('span');if(span)span.textContent=match?(match.display_name||match.handle||match.connection_status)+' · '+match.connection_status:'Not connected';});}
    const prefs=await client.from('notification_preferences').select('*').eq('owner_id',user.id).maybeSingle();
    if(prefs.error)throw prefs.error;
    const root=$('ng-notification-controls');
    if(root){
      root.innerHTML='';
      const values=prefs.data||{in_app_enabled:true,email_enabled:true,push_enabled:false,approval_updates:true,publishing_updates:true,connection_alerts:true,weekly_analytics:true};
      const labels=[['in_app_enabled','In-app notifications'],['email_enabled','Email notifications'],['push_enabled','Push notifications'],['approval_updates','Approval updates'],['publishing_updates','Publishing updates'],['connection_alerts','Connection alerts'],['weekly_analytics','Weekly analytics summary']];
      labels.forEach(([key,label])=>{
        const row=document.createElement('label');row.style.cssText='display:flex;align-items:center;justify-content:space-between;gap:12px;padding:10px 2px;border-bottom:1px solid #17385c;color:#eaf3ff;font-size:13px';
        const span=document.createElement('span');span.textContent=label;
        const input=document.createElement('input');input.type='checkbox';input.checked=!!values[key];input.addEventListener('change',async()=>{
          const next=Object.assign({},values,{[key]:input.checked,owner_id:user.id,timezone:'Asia/Kolkata',updated_at:new Date().toISOString()});
          const {error}=await client.from('notification_preferences').upsert(next,{onConflict:'owner_id'});
          if(error){input.checked=!input.checked;const note=$('ng-notification-note');if(note)note.textContent='Could not save: '+error.message;}
          else Object.assign(values,next);
        });
        row.append(span,input);root.append(row);
      });
    }
  }
  async function refresh(){
    try{
      await loadBase();
      if(page==='content.html')renderContent();
      if(page==='channels.html'){
        renderChannels();
        const mode=settings&&settings.approval_mode==='auto';
        if($('publishing-mode-label'))$('publishing-mode-label').textContent=mode?'Auto Approval Mode — ON':'Manual Approval Mode — ON';
        if($('auto-approval-label'))$('auto-approval-label').textContent=mode?'ON':'OFF';
      }
      if(page==='approvals.html'){
        renderApprovals();
        const mode=settings&&settings.approval_mode==='auto'?'auto':'manual';
        if($('manualMode'))$('manualMode').classList.toggle('selected',mode==='manual');
        if($('autoMode'))$('autoMode').classList.toggle('selected',mode==='auto');
        if($('modeNote'))$('modeNote').textContent=mode==='manual'?'Manual Approval is active. Every post requires your explicit approval.':'Auto mode preference saved; no automatic approval worker is active.';
      }
      if(page==='schedule.html'){
        const slots=settings&&settings.daily_idea_times||['08:00:00','14:00:00','18:00:00'];
        ['Morning','Afternoon','Evening'].forEach((name,i)=>{const input=$('slot'+name);if(input)input.value=String(slots[i]||'08:00').slice(0,5);});
        await renderSchedule();
      }
      if(page==='analytics.html')await loadAnalytics();
      if(page==='dashboard.html'||page==='index.html')await renderDashboard();
      if(page==='settings.html')await renderSettings();
    }catch(e){
      const msg='Workspace data could not be loaded: '+(e.message||'Unknown error');
      ['draftNote','modeNote','slotNote','scheduleNote'].forEach(id=>setNote(id,msg,true));
      const status=document.querySelector('.ng-analytics-status');if(status)status.textContent=msg;
    }
  }
  function bindPage(){
    if($('draftForm')){
      $('draftForm').onsubmit=null;
      $('draftForm').addEventListener('submit',async e=>{e.preventDefault();try{await saveDraft(e.currentTarget);}catch(err){setNote('draftNote',err.message,true);}});
      if($('copySeo'))$('copySeo').addEventListener('click',()=>navigator.clipboard?.writeText(['draftTitle','draftCaption','draftHash','draftTags'].map(id=>$(id)?.value||'').filter(Boolean).join('\n')));
    }
    if($('manualMode')){$('manualMode').onclick=null;$('manualMode').addEventListener('click',()=>setApprovalMode('manual').catch(e=>setNote('modeNote',e.message,true)));}
    if($('autoMode')){$('autoMode').onclick=null;$('autoMode').addEventListener('click',()=>setApprovalMode('auto').catch(e=>setNote('modeNote',e.message,true)));}
    if($('manual-approval-mode'))$('manual-approval-mode').addEventListener('click',()=>setApprovalMode('manual').catch(e=>setNote('approval-mode-note',e.message,true)));
    if($('auto-approval-mode'))$('auto-approval-mode').addEventListener('click',()=>setApprovalMode('auto').catch(e=>setNote('approval-mode-note',e.message,true)));
    if($('dash1-manual-approval')){$('dash1-manual-approval').onclick=null;$('dash1-manual-approval').addEventListener('click',()=>setApprovalMode('manual').catch(()=>{}));}
    if($('dash1-auto-approval')){$('dash1-auto-approval').onclick=null;$('dash1-auto-approval').addEventListener('click',()=>setApprovalMode('auto').catch(()=>{}));}
    if($('saveSlots')){$('saveSlots').onclick=null;$('saveSlots').addEventListener('click',()=>saveDailyTimes().catch(e=>setNote('slotNote',e.message,true)));}
    if($('scheduleForm')){$('scheduleForm').onsubmit=null;$('scheduleForm').addEventListener('submit',e=>{e.preventDefault();scheduleContent().catch(err=>setNote('scheduleNote',err.message,true));});}
    if($('analyticsPeriod'))$('analyticsPeriod').addEventListener('change',()=>loadAnalytics().catch(()=>{}));
  }
  function renderProfileAuthEntry(){
    const links=document.querySelector('.ng-profile-menu .ng-profile-links');
    if(!links)return;
    links.querySelectorAll('[data-ng-auth-entry],a[href="./login.html"]').forEach(node=>node.remove());
    const item=document.createElement('a');
    item.dataset.ngAuthEntry='true';
    item.innerHTML=user?'<span>↪</span>Logout<i>›</i>':'<span>↪</span>Login / Sign Up<i>›</i>';
    if(user){
      item.href='#';
      item.addEventListener('click',async event=>{
        event.preventDefault();
        item.style.pointerEvents='none';
        item.style.opacity='.65';
        const {error}=await client.auth.signOut();
        if(error){
          item.style.pointerEvents='';
          item.style.opacity='';
          item.lastChild.textContent='!';
          return;
        }
        location.href='./login.html';
      });
    }else{
      item.href='./login.html';
    }
    links.append(item);
  }
  function showAuth(){
    showAuthPanel();
    renderProfileAuthEntry();
    if(user)setSignedIn();
    else if(authMessage)authMessage.textContent='Sign in to enable secure database access. Local-only saving is disabled.';
  }
  window.NGWorkspace={
    client,
    getUser:()=>user,
    refresh,
    signIn:async email=>client.auth.signInWithOtp({email,options:{emailRedirectTo:location.origin+location.pathname}}),
    signOut:()=>client.auth.signOut()
  };

  // Keep the right-side profile menu on the same page when Chrome refreshes.
  (function(){
    const key='ngNextGenProfileMenuOpen';
    const trigger=document.getElementById('ng-profile-trigger');
    const menu=document.getElementById('ng-profile-menu');
    const backdrop=document.getElementById('ng-profile-backdrop');
    if(!trigger||!menu||!backdrop)return;
    function open(){
      menu.classList.add('is-open');
      menu.setAttribute('aria-hidden','false');
      backdrop.hidden=false;
      trigger.setAttribute('aria-expanded','true');
      document.body.classList.add('ng-profile-open');
    }
    function close(){
      menu.classList.remove('is-open');
      menu.setAttribute('aria-hidden','true');
      backdrop.hidden=true;
      trigger.setAttribute('aria-expanded','false');
      document.body.classList.remove('ng-profile-open');
      try{sessionStorage.removeItem(key)}catch(e){}
    }
    trigger.addEventListener('click',()=>setTimeout(()=>{
      try{if(menu.classList.contains('is-open'))sessionStorage.setItem(key,'1');else close()}catch(e){}
    },0));
    backdrop.addEventListener('click',close);
    menu.querySelectorAll('a').forEach(a=>a.addEventListener('click',close));
    document.addEventListener('keydown',e=>{if(e.key==='Escape')close()});
    window.addEventListener('pagehide',()=>{
      try{if(menu.classList.contains('is-open'))sessionStorage.setItem(key,'1')}catch(e){}
    });
    try{if(sessionStorage.getItem(key)==='1')open()}catch(e){}
  })();

  bindPage();
  showAuth();
  client.auth.getSession().then(({data})=>{
    user=data&&data.session?data.session.user:null;
    showAuth();
    if(user)refresh();
  });
  client.auth.onAuthStateChange((_event,session)=>{
    user=session&&session.user?session.user:null;
    showAuth();
    if(user)refresh();
  });
})();