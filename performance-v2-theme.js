/* Theme controls on mobile and desktop. Preserves all existing prototype flows. */
(function () {
  const iconSun='<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.93 4.93l1.41 1.41m11.32 11.32 1.41 1.41M2 12h2m16 0h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>';
  const iconMoon='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20.5 14A8.5 8.5 0 0 1 10 3.5 8.5 8.5 0 1 0 20.5 14Z"/></svg>';
  try {
    const saved=localStorage.getItem('northstar-v2-appearance');
    if(saved==='light'||saved==='dark')state.theme=saved;
  }catch (_) { /* Storage is not required in the preview. */ }
  const baseRender=render;
  render=function() {
    baseRender();
    try{localStorage.setItem('northstar-v2-appearance',state.theme)}catch(_){}
    const host=app.querySelector('.v2-top')||app.querySelector('.app-topbar');
    const themeButton=document.createElement('button');
    themeButton.type='button';
    themeButton.className='theme-switch';
    themeButton.setAttribute('aria-label',state.theme==='dark'?'Switch to light mode':'Switch to dark mode');
    themeButton.setAttribute('title',state.theme==='dark'?'Light mode':'Dark mode');
    themeButton.innerHTML=state.theme==='dark'?iconSun:iconMoon;
    themeButton.addEventListener('click',()=>{
      const scroller=app.querySelector('.app-scroll');
      const previousScroll=scroller?.scrollTop||0;
      state.theme=state.theme==='dark'?'light':'dark';
      render();
      const next=app.querySelector('.app-scroll');
      if(next) next.scrollTop=previousScroll;
    });
    if(host){
      const right=host.querySelector('.v2-avatar, .profile-button');
      if(right){
        const group=document.createElement('div');
        group.className='theme-switch-group';
        right.replaceWith(group);
        group.append(themeButton,right);
      }else{
        host.append(themeButton);
      }
    }else{
      const onboarding=app.querySelector('.app-shell.onboarding');
      if(onboarding)onboarding.append(themeButton);
    }
  };
  render();
})();
