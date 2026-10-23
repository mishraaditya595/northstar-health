/* Northstar Performance v2 — enhanced prototype views.
   Existing state machine, privacy flows and demo interactions remain intact. */
const nsIcon = (name,size=20) => {
 const paths={
 activity:'<path d="M3 12h4l3-8 4 16 3-8h4"/>',
 dumbbell:'<path d="m6.5 6.5 11 11M4 9l5-5M2 7l5-5m10 20 5-5m-3 3 3-3M9 4l11 11M4 9l5-5M2 7l5-5m10 20 5-5"/>',
 moon:'<path d="M20.5 14A8.5 8.5 0 0 1 10 3.5 8.5 8.5 0 1 0 20.5 14Z"/>',
 steps:'<path d="M5 17c1-3 3-3 5-2 2 2 2 4-1 5-3 1-5 0-4-3ZM12 8c1-3 3-3 5-2s3 4 1 6c-2 1-4 0-6-4Z"/>',
 heart:'<path d="M20.8 4.6a5.6 5.6 0 0 0-7.9 0L12 5.5l-.9-.9a5.6 5.6 0 0 0-7.9 7 7 0 0 0 0 9.8L12 22l8.8-7.6a7 7 0 0 0 0-9.8Z"/>',
 arrow:'<path d="M5 12h14m-6-6 6 6-6 6"/>',
 trophy:'<path d="M8 21h8M12 17v4M7 4h10v7a5 5 0 0 1-10 0V4ZM7 6H4v3a4 4 0 0 0 4 4m9-7h3v3a4 4 0 0 1-4 4"/>',
 chevron:'<path d="m9 18 6-6-6-6"/>',
 settings:'<circle cx="12" cy="12" r="3"/><path d="m19.4 15 .1.1 1.4 1.1-1.5 2.6-1.7-.6a8 8 0 0 1-1.7 1L15.7 21h-3l-.4-1.8a8 8 0 0 1-1.7-1l-1.7.6-1.5-2.6 1.4-1.1a8 8 0 0 1 0-2l-1.4-1.1 1.5-2.6 1.7.6a8 8 0 0 1 1.7-1L12.7 7h3l.4 1.8a8 8 0 0 1 1.7 1l1.7-.6 1.5 2.6-1.4 1.1a8 8 0 0 1 0 2Z"/>'
 };
 return '<svg width="'+size+'" height="'+size+'" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(paths[name]||paths.activity)+'</svg>';
};
icon = function(name){ return nsIcon(({today:'activity',train:'dumbbell',progress:'trophy',health:'heart',sleep:'moon',steps:'steps',heart:'heart',weight:'activity',workout:'dumbbell',arrow:'arrow',settings:'settings'})[name]||'activity'); };
nav = function(active){
 const items=[['today','Today','activity'],['train','Train','dumbbell'],['progress','Progress','trophy'],['health','Health','heart']];
 return '<nav class="bottom-nav" aria-label="Main navigation">'+items.map(([id,label,glyph])=>'<button class="nav-item '+(active===id?'active':'')+'" data-action="'+id+'" aria-label="'+label+'" aria-current="'+(active===id?'page':'false')+'"><span class="nav-icon">'+nsIcon(glyph,21)+'</span>'+label+'</button>').join('')+'</nav>';
};
const v2Top=(label,title)=>'<div class="v2-top"><div><span class="v2-eyebrow">'+label+'</span><h1 class="v2-page-title">'+title+'</h1></div><button class="v2-avatar" data-action="settings" aria-label="Open settings">AL</button></div>';
const v2Section=(title,action,label='View all')=>'<div class="v2-section"><h3>'+title+'</h3>'+(action?'<button data-action="'+action+'">'+label+' ↗</button>':'')+'</div>';
const v2Stat=(iconName,label,value,unit,source,action,extra='')=>'<div class="v2-stat '+extra+'" data-action="'+action+'" role="button" tabindex="0" aria-label="'+label+': '+value+' '+unit+'. '+source+'"><span class="v2-stat-icon">'+nsIcon(iconName,19)+'</span><span class="v2-eyebrow">'+label+'</span><strong class="v2-stat-value">'+value+(unit?'<small> '+unit+'</small>':'')+'</strong><span class="v2-stat-foot">'+source+'</span></div>';
const v2Week=()=>'<div class="v2-week"><div class="v2-week-top"><strong>'+ (state.completedToday?'3 of 3 sessions':'2 of 3 sessions')+'</strong><span>This week</span></div><div class="v2-week-days">'+['M','T','W','T','F','S','S'].map((d,i)=>'<div class="v2-day '+([0,2].includes(i)||i===4&&state.completedToday?'done':i===4?'current':'')+'"><i>'+([0,2].includes(i)||i===4&&state.completedToday?'✓':i===4?'●':'·')+'</i>'+d+'</div>').join('')+'</div></div>';
renderToday=function(){
 return shell(v2Top('FRIDAY / 23 OCTOBER','Your day.')+
 '<div class="v2-hero"><div><div class="v2-hero-head"><span class="v2-live">'+(state.completedToday?'SESSION COMPLETE':'TODAY’S SESSION')+'</span><span class="v2-hero-badge">01 / 03 THIS WEEK</span></div><h2>SHOW UP.<br><em>GET STRONG.</em></h2><p>Full Body A · 5 exercises · ~45 min</p></div><div class="v2-hero-foot"><button class="primary-button" data-action="'+(state.completedToday?'session-detail':'start-workout')+'">'+(state.completedToday?'Review session':'Start workout')+' <span class="v2-arrow">↗</span></button><button class="v2-outline-btn" data-action="routine" aria-label="View workout plan">'+nsIcon('chevron',22)+'</button></div><div class="v2-bars"><span></span><span></span><span></span></div></div>'+
 v2Section('Health at a glance','health')+
 '<div class="v2-snapshot">'+v2Stat('moon','Sleep','6h 18','min','Apple Health · Today','sleep-detail','purple')+v2Stat('steps','Steps','6,420','','Updated 18:20','steps-detail')+v2Stat('heart','Resting HR','58','bpm','Apple Health · Today','heart-detail')+v2Stat('activity','Weight','74.2','kg','Manual · 22 Oct','weight-detail')+'</div>'+
 v2Section('Your consistency','weekly-review','Weekly review')+v2Week()+
 '<div class="v2-signal"><div class="v2-signal-icon">'+nsIcon('moon',22)+'</div><div><strong>Sleep context</strong><p>Your last recorded night was 52 minutes shorter than your recent average. This is context, not a readiness score.</p></div></div>', 'today');
};
renderTrain=function(){
 return shell(v2Top('BUILT FOR PROGRESSION','Training.')+
 '<div class="v2-workout-card"><span class="v2-workout-icon">'+nsIcon('dumbbell',34)+'</span><span class="v2-eyebrow" style="margin-top:17px">NEXT SESSION · STRENGTH</span><h3>Full Body A</h3><p>5 movements. 15 working sets.<br>One more session towards your goal.</p><button class="primary-button" data-action="start-workout">Begin training &nbsp; ↗</button></div>'+
 v2Section('This week','schedule','Edit schedule')+v2Week()+
 v2Section('Your routines','templates','Discover')+
 '<div class="v2-pr" role="button" tabindex="0" data-action="routine"><div><strong>Full Body A</strong><br><span>5 exercises · Gym · 45 min</span></div><span class="v2-up">'+nsIcon('chevron',20)+'</span></div>'+
 '<div class="v2-pr" role="button" tabindex="0" data-action="builder"><div><strong>Create a custom routine</strong><br><span>Build your own training split</span></div><span class="v2-up">＋</span></div>'+
 v2Section('Start with a plan','templates','All templates')+
 '<div class="v2-template-cover">3-DAY<br>FULL BODY <span>01 / STRENGTH</span></div>'+
 '<button class="secondary-button full-width" data-action="templates">Explore training templates ↗</button>', 'train');
};
renderProgress=function(){
 const chart='<svg viewBox="0 0 320 165" role="img" aria-label="Demo best set squat weight rises across four sessions from 52.5 to 60 kg"><defs><linearGradient id="nsChartFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d6ff60" stop-opacity=".25"/><stop offset="1" stop-color="#d6ff60" stop-opacity="0"/></linearGradient></defs><path d="M0 38H320M0 84H320M0 130H320" stroke="var(--line)" stroke-dasharray="3 5"/><path d="M9 127 C47 120 69 105 108 100 S167 80 214 61 S275 46 311 26 L311 151 L9 151Z" fill="url(#nsChartFill)"/><path d="M9 127 C47 120 69 105 108 100 S167 80 214 61 S275 46 311 26" fill="none" stroke="#bdea52" stroke-width="3.5" stroke-linecap="round"/><circle cx="311" cy="26" r="5" fill="#d6ff60"/><text x="246" y="17" fill="var(--muted)" font-size="11" font-weight="700">60 kg</text></svg>';
 return shell(v2Top('THE WORK ADDS UP','Progress.')+
 '<div class="v2-meter-card"><div class="v2-meter-head"><strong>Training consistency</strong><span>19–25 Oct</span></div><svg class="v2-meter-svg" viewBox="0 0 320 162" role="img" aria-label="2 of 3 weekly training sessions completed"><path d="M76 134 A92 92 0 1 1 244 134" stroke="var(--surface-soft)" stroke-width="17" fill="none" stroke-linecap="round"/><path d="M76 134 A92 92 0 0 1 192 49" stroke="var(--forest)" stroke-width="17" fill="none" stroke-linecap="round"/><text class="v2-meter-label" x="160" y="113" text-anchor="middle">'+(state.completedToday?'3/3':'2/3')+'</text><text class="v2-meter-sub" x="160" y="136" text-anchor="middle">SESSIONS COMPLETE</text></svg><button class="secondary-button full-width" data-action="weekly-review">Open weekly review</button></div>'+
 v2Section('Strength in motion','progress-detail','Details')+
 '<div class="v2-chart-card"><span class="v2-eyebrow">SQUAT / BEST SET</span><h3 style="font-size:28px;letter-spacing:-.07em;margin:9px 0 14px">60 kg <span style="font-size:12px;color:var(--muted);font-weight:600">× 8 reps</span></h3>'+chart+'<div class="v2-axis"><span>6 OCT</span><span>12 OCT</span><span>19 OCT</span><span>23 OCT</span></div></div>'+
 v2Section('Recent bests','progress-detail','See trends')+
 '<div class="v2-pr" data-action="progress-detail" role="button" tabindex="0"><div><strong>Squat</strong><br><span>60 kg × 8 · 23 Oct</span></div><span class="v2-up">↑ 2.5 kg</span></div><div class="v2-pr" data-action="progress-detail" role="button" tabindex="0"><div><strong>Bench press</strong><br><span>45 kg × 8 · 21 Oct</span></div><span class="v2-up">↑ 2.5 kg</span></div>', 'progress');
};
renderHealth=function(){
 return shell(v2Top('YOUR DATA, YOUR PACE','Health.')+
 '<div class="v2-source"><span class="v2-source-dot"></span> APPLE HEALTH CONNECTED <span style="margin-left:auto">SYNCED 18:20</span></div>'+
 '<div class="v2-health-feature"><span class="v2-eyebrow">LAST NIGHT / SLEEP</span><h3>6h 18<small> min</small></h3><p>Recent average 7h 10m · From Apple Health</p><svg width="100%" height="60" viewBox="0 0 300 60" aria-hidden="true" style="margin-top:18px"><path d="M0 41H300" stroke="#726693" stroke-dasharray="3 5"/><path d="M0 38 Q28 18 54 26 T110 30 T166 18 T222 34 T298 15" stroke="#ccb5ff" fill="none" stroke-width="3" stroke-linecap="round"/></svg><button data-action="sleep-detail">Explore sleep trends ↗</button></div>'+
 v2Section('Your vital snapshots')+
 '<div class="v2-health-metrics">'+v2Stat('steps','Movement','6,420','','Steps · Today','steps-detail')+v2Stat('heart','Resting HR','58','bpm','Today · Apple Health','heart-detail')+v2Stat('activity','Weight','74.2','kg','22 Oct · Manual','weight-detail')+v2Stat('activity','Workouts','2','','This week · Logger','session-detail')+'</div>'+
 v2Section('Connected ecosystem','connections','Manage')+
 '<button class="v2-health-link" data-action="connections"><span style="color:var(--forest)">'+nsIcon('heart',20)+'</span> Apple Health + Apple Watch <span>›</span></button>'+
 '<p class="muted" style="font-size:11px;line-height:1.5;margin:14px 2px">Values are illustrative records, not medical interpretations. Missing records are never displayed as zero.</p>', 'health');
};
renderActiveWorkout=function(){
 const rows=state.workout.weight.map((w,i)=>'<div class="v2-set '+(i<state.workout.completedSets?'done':'')+'"><strong>'+(i+1)+'</strong><span>57.5 × 8</span><input type="number" aria-label="Set '+(i+1)+' weight in kg" value="'+w+'"><input type="number" aria-label="Set '+(i+1)+' reps" value="'+state.workout.reps[i]+'"><button aria-label="'+(i<state.workout.completedSets?'Set '+(i+1)+' done':'Complete set '+(i+1))+'" data-action="complete-set" data-set="'+i+'">'+(i<state.workout.completedSets?'✓':'↗')+'</button></div>').join('');
 return '<div class="app-shell workout-shell v2-workout-shell"><div class="app-scroll"><div class="v2-top"><div><span class="v2-eyebrow">LIVE TRAINING / 01 OF 05</span><h1 class="v2-page-title">Squat.</h1></div><button class="v2-avatar" data-action="minimise-workout" aria-label="Minimize workout">↓</button></div>'+
 '<div class="v2-hero"><div><span class="v2-live">SESSION IN PROGRESS</span><h2>ONE MORE<br><em>REP.</em></h2></div><p>Full Body A · 3 working sets · 90 sec rest</p></div>'+
 '<div class="v2-section"><h3>Working sets</h3><button data-action="workout-note">Add note ↗</button></div><div class="v2-set-header"><span>SET</span><span>LAST</span><span>KG</span><span>REPS</span><span>LOG</span></div>'+rows+
 '<div class="v2-actions"><button class="secondary-button" data-action="add-set">＋ Add set</button><button class="secondary-button" data-action="workout-note">Effort / notes</button></div>'+
 '<div class="v2-exercise-next"><span class="v2-eyebrow">UP NEXT / 02 OF 05</span><strong>Bench press</strong><p>3 sets × 8 reps · 45 kg target</p></div><button class="v2-workout-end" data-action="finish-review">Finish & review session ↗</button></div>'+(state.overlay?renderOverlay():'')+'</div>';
};
const originalRail=renderRail;
renderRail=function(){
 return originalRail().replace('Playground controls','Design playground').replace('What to notice','Design approach').replace('The workout logger keeps previous numbers visible while today\\'s set stays editable.','High contrast and large numerals prioritize performance data and one-handed logging.').replace('Health context is dated and sourced, never turned into a medical readiness score.','Health data stays clearly sourced; navigation uses subtle translucency and content cards remain opaque.');
};
state.theme='dark';
render();
