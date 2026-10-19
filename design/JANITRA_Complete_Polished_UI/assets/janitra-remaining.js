
window.JANITRA = {
  toast(message){const el=document.getElementById('notice-dialog'); if(!el){alert(message);return};el.querySelector('[data-msg]').textContent=message;el.classList.add('open');},
  close(){document.querySelectorAll('.dialog.open').forEach(d=>d.classList.remove('open'))},
  confirm(title,msg,action){const d=document.getElementById('confirm-dialog');d.querySelector('[data-title]').textContent=title;d.querySelector('[data-desc]').textContent=msg;d.classList.add('open');d.querySelector('[data-confirm]').onclick=()=>{d.classList.remove('open');action()}},
  preview(action){this.toast(action+' is a UI prototype. Codex will connect this screen to secure Supabase operations in Flutter.')},
  submitForm(event,action){event.preventDefault();if(!event.target.reportValidity())return;this.preview(action)},
  toggleDay(button){button.setAttribute('aria-pressed',button.getAttribute('aria-pressed')!=='true')},
  setTab(button){document.querySelectorAll('.tab').forEach(b=>b.classList.remove('active'));button.classList.add('active');const p=document.querySelector('#range-custom');if(p)p.classList.toggle('hide',button.dataset.value!=='custom');},
  filterPeople(query){const q=query.toLowerCase();let num=0;document.querySelectorAll('[data-person]').forEach(n=>{let match=n.dataset.person.toLowerCase().includes(q);n.classList.toggle('hide',!match);if(match)num++});const empty=document.getElementById('directory-empty');if(empty)empty.classList.toggle('hide',num!==0)},
  addShift(){const t=document.querySelector('#shift-template');const host=document.querySelector('#shifts');if(t&&host){const node=t.content.cloneNode(true);host.appendChild(node)}},
  activityChange(sel){const c=document.querySelector('#custom-activity');if(c)c.classList.toggle('hide',sel.value!=='custom')},
  reportExport(format){this.toast(format+' export is a UI preview only. Official '+format+' files will be generated from authorized Supabase data in the Flutter app.')},
  openFull(){document.getElementById('full-preview')?.classList.add('open')}
};
