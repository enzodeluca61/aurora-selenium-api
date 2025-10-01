# Deployment su Render - Aurora Selenium Server

## Istruzioni per il deployment del server Selenium su Render

### 1. Preparazione Repository

Prima del deployment, assicurati che questi file siano nella root del progetto:
- `selenium_api_server.py` ✅
- `selenium_scraper.py` ✅
- `requirements.txt` ✅
- `Dockerfile` ✅
- `.env.example` ✅

### 2. Creazione Account Render

1. Vai su [render.com](https://render.com)
2. Registrati con GitHub/Google
3. Conferma email se richiesto

### 3. Deployment del Server

#### Opzione A: Deploy da GitHub (Consigliato)
1. Carica i file su un repository GitHub
2. Su Render, clicca "New +" → "Web Service"
3. Connetti il repository GitHub
4. Configura:
   - **Name**: `aurora-selenium-api`
   - **Environment**: `Docker`
   - **Region**: `Frankfurt` (Europa)
   - **Branch**: `main`

#### Opzione B: Deploy manuale
1. Su Render, clicca "New +" → "Web Service"
2. Scegli "Deploy an existing image from a registry"
3. Carica il Dockerfile e i file

### 4. Configurazione Environment Variables

Nella dashboard del servizio, vai su "Environment" e aggiungi:

```
PORT=10000
FLASK_ENV=production
CHROME_HEADLESS=true
```

### 5. Configurazione Build

Se usi GitHub, Render rileverà automaticamente il Dockerfile.

Se hai problemi, specifica:
- **Build Command**: `docker build -t aurora-selenium .`
- **Start Command**: `gunicorn --bind 0.0.0.0:$PORT selenium_api_server:app`

### 6. Deploy e Test

1. Clicca "Create Web Service"
2. Attendi il build (5-10 minuti)
3. Una volta completato, otterrai un URL tipo:
   `https://aurora-selenium-api.onrender.com`

### 7. Test dell'URL

Testa che il server funzioni:
```bash
curl https://aurora-selenium-api.onrender.com/health
```

Dovresti ricevere:
```json
{"status": "ok", "service": "selenium-api-server"}
```

### 8. Configurazione App Flutter

L'app è già configurata per usare automaticamente Render!

Il sistema di discovery proverà nell'ordine:
1. `https://aurora-selenium-api.onrender.com` (Render)
2. `http://192.168.1.13:5001` (rete locale)
3. Altri fallback

### 9. Monitoraggio

- Dashboard Render: logs in tempo reale
- L'app Flutter mostrerà nei log quale server sta usando
- Piano gratuito: 750 ore/mese (sufficiente per uso normale)

### 10. Troubleshooting

**Build fallisce?**
- Verifica che `Dockerfile` sia nella root
- Controlla i logs di build su Render

**Server non risponde?**
- Render potrebbe mettere il servizio in "sleep" dopo inattività
- Il primo scraping dopo sleep può richiedere 30-60 secondi

**App non trova server?**
- Verifica l'URL del servizio su Render
- Aggiorna l'URL in `results_service.dart` se necessario

### 11. Costi

- **Piano gratuito**: 750 ore/mese, sleep dopo inattività
- **Piano base ($7/mese)**: nessun sleep, always-on

Per uso normale, il piano gratuito è sufficiente!

### Note Importanti

- Render usa HTTPS automaticamente
- Il server va in sleep dopo 15 minuti di inattività (piano gratuito)
- Chrome/Selenium funzionano correttamente nell'ambiente Docker di Render
- I logs sono accessibili dalla dashboard Render