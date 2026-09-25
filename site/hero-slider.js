(function(){
'use strict';
const hero=document.querySelector('.premium-hero');if(!hero)return;
const slides=[...hero.querySelectorAll('.hp-slide')],dotsBox=hero.querySelector('#heroDots'),progress=hero.querySelector('#heroProgress');
const reduce=matchMedia('(prefers-reduced-motion: reduce)');let current=0,timer=null,paused=reduce.matches,hover=false,focused=false,touch=null;const duration=4500;
let userPause=null;const pauseButton=document.createElement('button');pauseButton.type='button';pauseButton.className='hp-pause';hero.querySelector('.hp-slider-ui').appendChild(pauseButton);
function updatePause(){const en=document.documentElement.lang==='en';pauseButton.textContent=paused?(en?'Resume slides':'تشغيل الشرائح'):(en?'Pause slides':'إيقاف الحركة');pauseButton.setAttribute('aria-label',pauseButton.textContent);}
pauseButton.addEventListener('click',()=>{paused=!paused;userPause=paused;updatePause();schedule();});
new MutationObserver(updatePause).observe(document.documentElement,{attributes:true,attributeFilter:['lang']});reduce.addEventListener('change',()=>{paused=userPause===null?reduce.matches:userPause;updatePause();});updatePause();
const dots=slides.map((slide,i)=>{slide.setAttribute('role','group');slide.setAttribute('aria-roledescription','slide');slide.setAttribute('aria-label',(i+1)+' / '+slides.length);const b=document.createElement('button');b.type='button';b.className='hp-dot';b.setAttribute('aria-label','عرض الشريحة '+(i+1));b.addEventListener('click',()=>show(i));dotsBox.appendChild(b);return b;});
function localize(){const en=document.documentElement.lang==='en';hero.querySelectorAll('.hp-content').forEach(el=>el.style.direction=en?'ltr':'rtl');schedule();}
new MutationObserver(localize).observe(document.documentElement,{attributes:true,attributeFilter:['lang']});
function stop(){clearTimeout(timer);timer=null;progress.style.transition='none';progress.style.width='0';}
function schedule(){stop();if(paused||hover||focused||document.hidden)return;requestAnimationFrame(()=>{if(!timer)return;progress.style.transition='width '+duration+'ms linear';progress.style.width='100%';});timer=setTimeout(()=>show(current+1),duration);}
function show(n){current=(n+slides.length)%slides.length;slides.forEach((s,i)=>{s.classList.toggle('hp-active',i===current);s.inert=i!==current;s.setAttribute('aria-hidden',String(i!==current));dots[i].classList.toggle('hp-active',i===current);dots[i].setAttribute('aria-current',i===current?'true':'false');});schedule();}
hero.querySelector('#heroNext').addEventListener('click',()=>show(current+1));hero.querySelector('#heroPrev').addEventListener('click',()=>show(current-1));
hero.addEventListener('mouseenter',()=>{hover=true;schedule();});hero.addEventListener('mouseleave',()=>{hover=false;schedule();});hero.addEventListener('focusin',()=>{focused=true;schedule();});hero.addEventListener('focusout',()=>setTimeout(()=>{focused=hero.contains(document.activeElement);schedule();},0));document.addEventListener('visibilitychange',schedule);reduce.addEventListener('change',()=>{paused=userPause===null?reduce.matches:userPause;updatePause();schedule();});
hero.addEventListener('keydown',e=>{if(e.key==='ArrowLeft'||e.key==='ArrowRight'){e.preventDefault();show(current+(e.key==='ArrowLeft'?1:-1));}});
hero.addEventListener('touchstart',e=>{touch={x:e.touches[0].clientX,y:e.touches[0].clientY};stop();},{passive:true});hero.addEventListener('touchend',e=>{if(!touch)return;const dx=e.changedTouches[0].clientX-touch.x,dy=e.changedTouches[0].clientY-touch.y;touch=null;if(Math.abs(dx)>55&&Math.abs(dx)>Math.abs(dy)*1.4)show(current+(dx>0?1:-1));else schedule();},{passive:true});hero.addEventListener('touchcancel',()=>{touch=null;schedule();},{passive:true});localize();show(0);
})();
