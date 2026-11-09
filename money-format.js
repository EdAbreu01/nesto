/* Nesto: comma thousands, dot decimals. Storage and calculations stay numeric. */
window.NestoMoney=(()=>{
const selector='input[data-amount]:not([readonly]),input[name="amount"],input[name="target"],#f_capital,#f_balance,#f_amount,#simCapital,#simContribution';
const formatter=new Intl.NumberFormat('en-US',{useGrouping:true,minimumFractionDigits:2,maximumFractionDigits:2});
const clean=value=>String(value??'').replace(/,/g,'').trim();
function parse(value){const raw=clean(value);return /^-?(?:\d+(?:\.\d{0,2})?|\.\d{1,2})$/.test(raw)?Number(raw):NaN}
function format(value){const number=typeof value==='number'?value:parse(value);return Number.isFinite(number)?formatter.format(number):''}
function draft(value){const raw=clean(value);if(!/^-?\d*(?:\.\d{0,2})?$/.test(raw))return String(value);const sign=raw.startsWith('-')?'-':'',unsigned=sign?raw.slice(1):raw,[whole,fraction]=unsigned.split('.');const grouped=whole.replace(/^0+(?=\d)/,'').replace(/\B(?=(\d{3})+(?!\d))/g,',');return sign+grouped+(fraction!==undefined?'.'+fraction:'')}
function isMoney(el){return el instanceof HTMLInputElement&&el.matches(selector)&&!el.readOnly}
function validate(el){const number=parse(el.value);let message='';if(el.value.trim()){if(!Number.isFinite(number))message='Usa un monto como 1,234.56, con hasta dos decimales.';else if(el.hasAttribute('min')&&number<Number(el.getAttribute('min')))message='El monto mínimo es '+format(Number(el.getAttribute('min')))+'.';else if(el.hasAttribute('max')&&number>Number(el.getAttribute('max')))message='El monto máximo es '+format(Number(el.getAttribute('max')))+'.'}else if(el.required)message='Introduce un monto.';el.setCustomValidity(message);return !message}
function prepare(el){if(!isMoney(el))return;el.type='text';el.inputMode='decimal';el.dataset.nestoMoney='true';if(!el.placeholder)el.placeholder='0.00';if(document.activeElement!==el&&el.value!==''&&Number.isFinite(parse(el.value)))el.value=format(el.value);validate(el)}
function scan(){document.querySelectorAll(selector).forEach(prepare)}
document.addEventListener('input',event=>{const el=event.target;if(!isMoney(el))return;const position=el.selectionStart??el.value.length,logical=el.value.slice(0,position).replace(/,/g,'').length,next=draft(el.value);el.value=next;let caret=0,count=0;while(caret<next.length&&count<logical){if(next[caret]!==',')count++;caret++}try{el.setSelectionRange(caret,caret)}catch{}validate(el)},true);
document.addEventListener('change',event=>{const el=event.target;if(!isMoney(el))return;if(validate(el)&&el.value!=='')el.value=format(el.value)},true);
document.addEventListener('focusout',event=>{const el=event.target;if(isMoney(el)&&validate(el)&&el.value!=='')el.value=format(el.value)},true);
document.addEventListener('reset',()=>queueMicrotask(scan),true);
const observer=new MutationObserver(()=>scan());function start(){scan();observer.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['open']})}if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
return{parse,format,draft,scan};
})();
