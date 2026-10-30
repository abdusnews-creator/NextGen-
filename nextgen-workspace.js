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

  function setNote(id, message, isError){
    const node=$(id); if(!node)return;
    node.textContent=message;
    node.style.color=isError?'#ffadad':'#a8c1e8';
  }
  function showAuthPanel(){
    if(!main || authPanel)return;
    authPanel=document.createElement('section');
    authPanel.className='page-panel';
    authPanel.id='ng-workspace-auth';
    authPanel.style.cssText='margin:10px 11px 14px;padding:14px;border:1px solid #17436c;border-radius:15px;background:linear-gradient(145deg,#081f3a,#06172c);color:#eef5ff';
    const heading=document.createElement('h2');heading.textContent='Connect your NextGen workspace';
    const description=document.createElement('p');description.className='muted';description.textContent='Sign in with your workspace email to save drafts, approvals, schedules and settings securely.';
    const input=document.createElement('input');input.type='email';input.autocomplete='email';input.placeholder='Your email address';input.required=true;input.id='ng-workspace-email';input.style.cssText='width:100%;min-height:42px;margin:8px 0;padding:10px;border:1px solid #285a89;border-radius:9px;background:#07142d;color:#fff';
    const button=document.createElement('button');button.type='button';button.textContent='Send secure sign-in link';button.style.cssText='min-height:40px;padding:8px 14px;border:1px solid #21bdf1;border-radius:9px;background:#0c3154;color:#fff;font-weight:700';
    authMessage=document.createElement('p');authMessage.className='muted';authMessage.style.cssText='font-size:12px;line-height:1.5;margin-top:8px';
    button.addEventListener('click',async function(){
      const email=input.value.trim();
      if(!email){authMessage.textContent='Enter your email address first.';return;}
      button.disabled=true;authMessage.textContent='Sending sign-in link…';
      const {error}=await client.auth.signInWithOtp({email,options:{emailRedirectTo:location.origin+location.pathname}});
      button.disabled=false;
      authMessage.textContent=error?'Sign-in link could not be sent: '+error.message:'Check your email and open the secure NextGen sign-in link on this device.';
    });
    authPanel.append(heading,description,input,button,authMessage);
    const intro=main.querySelector('.page-intro');
    if(intro&&intro.nextSibling)main.insertBefore(authPanel,intro.nextSibling);else main.insertBefore(authPanel,main.firstChild);
  }
  function setSignedIn(){
    if(!authPanel)return;
    authPanel.innerHTML='';
    const heading=document.createElement('h2');heading.textContent='Workspace connected';
    const info=document.createElement('p');info.className='muted';info.textContent='Signed in as '+(user.email||'authenticated user')+'. Your records are saved securely in NextGen.';
    const button=document.createElement('button');button.type='button';button.textContent='Sign out';button.style.cssText='min-height:36px;padding:7px 13px;border:1px solid #285a89;border-radius:9px;background:#07142d;color:#fff';
    button.addEventListener('click',async()=>{await client.auth.signOut();});
    authPanel.append(heading,info,button);
  }
  async function requireUser(){
    if(!user)throw new Error('Sign in to NextGen above to continue.');
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
    root.innerHTML='';
    if(!channels.length){empty(root,'No channels are saved in this workspace yet. Use Add Channel to verify and save a profile.');return;}
    channels.forEach(ch=>{
      const card=document.createElement('div');card.className='card '+({youtube:'yt',facebook:'fb',instagram:'ig',threads:'th'}[ch.platform]||'');
      const icon=document.createElement('div');icon.className='ico';icon.textContent=({youtube:'▶',facebook:'f',instagram:'◎',threads:'＠'}[ch.platform]||'•');
      const info=document.createElement('div');info.className='info';
      const name=document.createElement('b');name.textContent=ch.display_name||ch.platform;
      const handle=document.createElement('span');handle.textContent=ch.handle?'@'+String(ch.handle).replace(/^@/,''):'Profile name pending';
      info.append(name,handle);
      const status=document.createElement('div');status.className='st';status.textContent='Connection: '+ch.connection_status+(ch.is_paused?' · Paused':'');
      card.append(icon,info,status);root.append(card);
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
    if($('manualMode'))$('manualMode').classList.toggle('selected',!enabled);
    if($('autoMode'))$('autoMode').classList.toggle('selected',enabled);
    if($('modeNote'))$('modeNote').textContent=enabled?'Auto mode preference saved. No automatic approval or publishing worker is active; every post still needs an explicit approval action.':'Manual Approval is active. Every post requires your explicit approval.';
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
    const status=document.querySelector('.ng-analytics-status');
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
  }
  async function refresh(){
    try{
      await loadBase();
      if(page==='content.html')renderContent();
      if(page==='channels.html')renderChannels();
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
    if($('dash1-manual-approval')){$('dash1-manual-approval').onclick=null;$('dash1-manual-approval').addEventListener('click',()=>setApprovalMode('manual').catch(()=>{}));}
    if($('dash1-auto-approval')){$('dash1-auto-approval').onclick=null;$('dash1-auto-approval').addEventListener('click',()=>setApprovalMode('auto').catch(()=>{}));}
    if($('saveSlots')){$('saveSlots').onclick=null;$('saveSlots').addEventListener('click',()=>saveDailyTimes().catch(e=>setNote('slotNote',e.message,true)));}
    if($('scheduleForm')){$('scheduleForm').onsubmit=null;$('scheduleForm').addEventListener('submit',e=>{e.preventDefault();scheduleContent().catch(err=>setNote('scheduleNote',err.message,true));});}
    if($('analyticsPeriod'))$('analyticsPeriod').addEventListener('change',()=>loadAnalytics().catch(()=>{}));
  }
  function showAuth(){
    showAuthPanel();
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