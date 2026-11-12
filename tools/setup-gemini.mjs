// Local configuration migration. Existing credentials are preserved and never printed.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {saveProviderSettings} from '../companion/lib/providers.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const envPath=path.join(root,'companion','.env');
let body;try{body=await fs.readFile(envPath,'utf8');}catch(error){if(error.code!=='ENOENT')throw error;body=await fs.readFile(path.join(root,'companion','.env.example'),'utf8');}
for(const [name,value]of[['GEMINI_API_KEY',''],['GEMINI_MODEL','gemini-3.5-flash-lite']])if(!new RegExp('^\\s*'+name+'\\s*=','m').test(body))body+='\n'+name+'='+value+'\n';
await fs.writeFile(envPath,body,{mode:0o600});
await saveProviderSettings({provider:'gemini',model:'gemini-3.5-flash-lite'},path.join(root,'companion','data'));
console.log('Gemini selected. Add your Google AI Studio key to GEMINI_API_KEY in companion/.env, then restart the companion. Existing credentials were preserved.');
