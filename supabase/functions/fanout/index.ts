// Fanout unified: menerima pg_notify via HTTP dari trigger DB
// dan meneruskan ke FCM Topic (1 publish → N subscriber)
// Dipanggil oleh net.http_post dari trigger notify_*_fanout

import { isServiceRoleJwt, unauthorized } from '../_shared/auth.ts';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const FCM_PROJECTS = [{ id: 'chatyuk-7c9e4', envKey: 'FIREBASE_SERVICE_ACCOUNT' }];

function base64UrlEncode(s: string) {
  const b = new TextEncoder().encode(s);
  let bin = ''; for (const x of b) bin += String.fromCharCode(x);
  return btoa(bin).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
}
async function getAccessToken(saJson: any) {
  const now = Math.floor(Date.now()/1000);
  const header={alg:'RS256',typ:'JWT'}; const payload={iss:saJson.client_email, scope:FCM_SCOPE, aud:saJson.token_uri, iat:now, exp:now+3600};
  const signed=`${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}`;
  const key=await crypto.subtle.importKey('pkcs8', parsePem(saJson.private_key), {name:'RSASSA-PKCS1-v1_5', hash:'SHA-256'}, false, ['sign']);
  const sig=await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signed));
  const sigB64=btoa(String.fromCharCode(...new Uint8Array(sig))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
  const jwt=`${signed}.${sigB64}`;
  const r=await fetch(saJson.token_uri,{method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:`grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`});
  return (await r.json()).access_token;
}
function parsePem(pem:string){ const b64=pem.replace('-----BEGIN PRIVATE KEY-----','').replace('-----END PRIVATE KEY-----','').replace(/[^A-Za-z0-9+/=]/g,''); const raw=atob(b64); const a=new Uint8Array(raw.length); for(let i=0;i<raw.length;i++) a[i]=raw.charCodeAt(i); return a; }

async function sendTopic(topic:string, title:string, body:string, data:Record<string,string>, image?:string){
  const msg:any={ message:{ topic, data, android:{priority:'high'}, notification:{title, body} } };
  if(image) { msg.message.notification.image=image; msg.message.android.notification={image}; msg.message.apns={payload:{aps:{'mutable-content':1}}, fcm_options:{image}}; }
  for(const proj of FCM_PROJECTS){
    const saRaw=Deno.env.get(proj.envKey); if(!saRaw) continue;
    try{ const sa=JSON.parse(saRaw); const tok=await getAccessToken(sa);
      const res=await fetch(`https://fcm.googleapis.com/v1/projects/${proj.id}/messages:send`,{method:'POST', headers:{'Content-Type':'application/json', Authorization:`Bearer ${tok}`}, body:JSON.stringify(msg)});
      if(res.ok) return await res.text();
    }catch(_){ }
  }
  return null;
}

Deno.serve(async (req)=>{
  try{
    if(req.method!=='POST') return new Response('Method not allowed',{status:405});
    // Auth: hanya service_role (dipanggil trigger DB via service role).
    // Semua user biasa dilarang memicu push massal ke topic.
    if(!isServiceRoleJwt(req)) return unauthorized();
    const {type, id} = await req.json();
    const supabaseUrl=Deno.env.get('SUPABASE_URL')!; const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const headers={apikey:key, Authorization:`Bearer ${key}`, 'Content-Type':'application/json'};
    if(type==='online'){
      const r=await fetch(`${supabaseUrl}/rest/v1/profiles?select=nickname,avatar&id=eq.${id}`,{headers});
      const rows=await r.json(); const row=rows[0]; if(!row) return new Response('not found',{status:404});
      let avatar=row.avatar||''; if(avatar.startsWith('avatars/')) avatar=`https://fohcucyyejdryryoxitm.supabase.co/storage/v1/object/public/chat-photos/${avatar}`;
      await sendTopic(`online-${id}`, row.nickname||'User', `${row.nickname||'User'} online`, {type:'online', uid:id, nickname:row.nickname||'', avatarUrl:avatar, message:`${row.nickname||'User'} online`}, avatar.startsWith('http')?avatar:undefined);
    } else if(type==='timeline'){
      const r=await fetch(`${supabaseUrl}/rest/v1/posts?select=id,author_id,author_name,author_avatar,text&id=eq.${id}`,{headers});
      const rows=await r.json(); const row=rows[0]; if(!row) return new Response('not found',{status:404});
      let av=row.author_avatar||''; if(av.startsWith('avatars/')) av=`https://fohcucyyejdryryoxitm.supabase.co/storage/v1/object/public/chat-photos/${av}`;
      const preview=(row.text||'').slice(0,100);
      await sendTopic('timeline-all', row.author_name||'User', preview, {type:'timeline', postId:id, authorId:row.author_id, authorName:row.author_name||'', avatarUrl:av, message:preview}, av.startsWith('http')?av:undefined);
    } else if(type==='room'){
      await sendTopic(`room-${id}`, 'Room update', 'Ada aktivitas di room', {type:'room', roomId:id}, undefined);
    }
    return new Response(JSON.stringify({ok:true}),{status:200, headers:{'Content-Type':'application/json'}});
  }catch(e){ return new Response(JSON.stringify({error:String(e)}),{status:500}); }
});
