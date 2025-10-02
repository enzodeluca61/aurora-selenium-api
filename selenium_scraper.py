#!/usr/bin/env python3
"""
Selenium scraper per tuttocampo.it - Bypass CORS limitations
Estrae risultati specifici per Aurora Seriate 1967
"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from selenium.common.exceptions import TimeoutException, NoSuchElementException
import json
import time
import re
import sys
from supabase import create_client, Client
from datetime import datetime

class TuttocampoSeleniumScraper:
    # Configurazione Supabase
    SUPABASE_URL = 'https://hkhuabfxjlcidlodbiru.supabase.co'
    SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhraHVhYmZ4amxjaWRsb2RiaXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTYwNTM2MjAsImV4cCI6MjA3MTYyOTYyMH0.ywg26EFefan4H1sPySmrWS0ndh6gPjOyjfqCIUQ67Ws'

    # URL base templates per categorie che supportano giornate dinamiche
    CATEGORY_URL_TEMPLATES = {
        'PROMOZIONE': 'https://www.tuttocampo.it/Lombardia/Promozione/GironeA/Risultati',
        'U21': 'https://www.tuttocampo.it/Lombardia/Under21/GironeD/Risultati',
        'U19': 'https://www.tuttocampo.it/Lombardia/JunioresEliteU19/GironeC/Giornata{giornata}',
        'U18': 'https://www.tuttocampo.it/Lombardia/AllieviRegionaliU18/GironeD/Risultati',
        'U17': 'https://www.tuttocampo.it/Lombardia/AllieviRegionaliU17/GironeD/Risultati',
        'U16': 'https://www.tuttocampo.it/Lombardia/AllieviProvincialiU16/GironeDBergamo/Risultati',
        'U15': 'https://www.tuttocampo.it/Lombardia/GiovanissimiProvincialiU15/GironeCBergamo/Risultati',
        'U14': 'https://www.tuttocampo.it/Lombardia/GiovanissimiProvincialiU14/GironeCBergamo/Risultati',
    }

    # Mapping delle categorie ai loro team Aurora
    CATEGORY_TO_AURORA_TEAM = {
        'PROMOZIONE': 'PROMOZIONE',
        'U21': 'TERZA',
        'U19': 'JUNIORES',
        'U18': 'ALLIEVI',
        'U17': 'ALLIEVI',
        'U16': 'ALLIEVI',
        'U15': 'GIOVANISSIMI',
        'U14': 'GIOVANISSIMI',
    }

    # Opponents mapping per match specifici
    EXPECTED_OPPONENTS = {
        'PROMOZIONE': ['gorle', 'calcio gorle'],
        'U21': ['virescit'],
        'U19': ['citta di albino', 'città di albino', 'albino'],
        'U18': ['lallio calcio', 'lallio'],
        'U17': ['falco'],
        'U16': ['or.boccaleone', 'boccaleone'],
        'U14': ['barianese'],
    }

    def __init__(self, headless=True):
        """Inizializza il scraper Selenium con Chrome ottimizzato per velocità"""
        import os

        self.options = Options()
        if headless:
            self.options.add_argument('--headless=new')  # Nuovo headless mode

        # Configurazione minimalista per massima compatibilità container
        # Solo le opzioni strettamente necessarie per Render
        self.options.add_argument('--no-sandbox')
        self.options.add_argument('--disable-dev-shm-usage')
        self.options.add_argument('--disable-gpu')

        # Configurazione base per funzionamento
        self.options.add_argument('--window-size=800,600')
        self.options.add_argument('--disable-extensions')

        self.driver = None
        self.supabase = None

        # Diagnostic logging per debug Render
        import logging
        self.logger = logging.getLogger(__name__)
        self.logger.info("🔧 Chrome options configurate per Render:")

    def start(self):
        """Avvia il browser Chrome ottimizzato e inizializza Supabase"""
        try:
            print("🏁 Avvio Chrome ottimizzato per container...")

            # Log configurazione Chrome
            for arg in self.options.arguments:
                self.logger.info(f"   {arg}")

            # Verifica ChromeDriver esistente
            import shutil
            chromedriver_path = shutil.which("chromedriver")
            if chromedriver_path:
                print(f"✅ ChromeDriver trovato: {chromedriver_path}")

                # Verifica versione Chrome
                import subprocess
                try:
                    chrome_version = subprocess.check_output(['google-chrome', '--version'], stderr=subprocess.STDOUT, text=True)
                    print(f"🌐 Versione Chrome: {chrome_version.strip()}")
                except Exception as e:
                    print(f"⚠️ Impossibile verificare versione Chrome: {e}")
            else:
                print("❌ ChromeDriver non trovato nel PATH")
                return False

            # Prova ad avviare Chrome con timeout
            import signal
            import time

            def timeout_handler(signum, frame):
                raise TimeoutError("Chrome startup timeout")

            # Set timeout di 30 secondi per l'avvio di Chrome
            signal.signal(signal.SIGALRM, timeout_handler)
            signal.alarm(30)

            try:
                self.driver = webdriver.Chrome(options=self.options)
                signal.alarm(0)  # Cancella timeout
                print("✅ Chrome avviato con successo")
            except TimeoutError:
                signal.alarm(0)
                print("❌ Timeout avvio Chrome (30s)")
                return False
            except Exception as chrome_error:
                signal.alarm(0)
                print(f"❌ Errore specifico Chrome: {chrome_error}")
                print(f"❌ Tipo errore: {type(chrome_error).__name__}")

                # Diagnostici aggiuntivi per Render
                import os
                print(f"🔍 DISPLAY env: {os.getenv('DISPLAY', 'NOT SET')}")
                print(f"🔍 Xvfb running: {os.system('pgrep Xvfb > /dev/null') == 0}")
                print(f"🔍 Chrome binary exists: {os.path.exists('/usr/bin/google-chrome')}")
                print(f"🔍 Memory info: {os.system('free -h') if os.path.exists('/usr/bin/free') else 'N/A'}")

                return False

            # Timeout più brevi per velocità massima
            self.driver.implicitly_wait(2)
            self.driver.set_page_load_timeout(8)

            # Test semplice di Chrome
            try:
                self.driver.get("data:text/html,<html><body><h1>Test</h1></body></html>")
                print("✅ Chrome test page loaded successfully")
            except Exception as test_error:
                print(f"❌ Chrome test failed: {test_error}")
                return False

            # Inizializza Supabase
            self.supabase = create_client(self.SUPABASE_URL, self.SUPABASE_KEY)
            print("✅ Sistema inizializzato (Chrome + Supabase)")

            return True
        except Exception as e:
            print(f"❌ Errore generale avvio: {e}")
            print(f"❌ Tipo errore: {type(e).__name__}")
            import traceback
            print(f"❌ Traceback: {traceback.format_exc()}")
            return False

    def stop(self):
        """Chiude il browser"""
        if self.driver:
            self.driver.quit()

    def _clean_giornata_number(self, giornata_raw):
        """Rimuove i caratteri A o R dalla fine della giornata e ritorna solo il numero"""
        if not giornata_raw:
            return None

        giornata_str = str(giornata_raw).strip().upper()
        # Rimuovi A o R alla fine
        if giornata_str.endswith('A') or giornata_str.endswith('R'):
            giornata_str = giornata_str[:-1]

        # Estrai solo i numeri
        import re
        numbers = re.findall(r'\d+', giornata_str)
        if numbers:
            return numbers[0]
        return None

    def _get_current_giornata_from_supabase(self, category):
        """Ottiene il numero della giornata corrente da Supabase per la categoria specifica"""
        if not self.supabase:
            print("❌ Supabase non inizializzato")
            return None

        try:
            aurora_team = self.CATEGORY_TO_AURORA_TEAM.get(category)
            if not aurora_team:
                print(f"❌ Team Aurora non trovato per categoria {category}")
                return None

            # Cerca partite recenti per questa categoria/team
            today = datetime.now()

            response = self.supabase.table('matches').select('giornata').eq('aurora_team', aurora_team).gte('date', today.strftime('%Y-%m-%d')).order('date').limit(1).execute()

            if response.data and len(response.data) > 0:
                giornata_raw = response.data[0].get('giornata')
                if giornata_raw:
                    cleaned_number = self._clean_giornata_number(giornata_raw)
                    print(f"✅ Giornata trovata per {category}: {giornata_raw} -> {cleaned_number}")
                    return cleaned_number

            # Fallback: cerca l'ultima partita disponibile
            response = self.supabase.table('matches').select('giornata').eq('aurora_team', aurora_team).order('date', desc=True).limit(1).execute()

            if response.data and len(response.data) > 0:
                giornata_raw = response.data[0].get('giornata')
                if giornata_raw:
                    cleaned_number = self._clean_giornata_number(giornata_raw)
                    print(f"✅ Ultima giornata disponibile per {category}: {giornata_raw} -> {cleaned_number}")
                    return cleaned_number

            print(f"❌ Nessuna giornata trovata per {category}")
            return None

        except Exception as e:
            print(f"❌ Errore durante la lettura da Supabase: {e}")
            return None

    def _build_category_url(self, category):
        """Costruisce l'URL per la categoria usando la giornata da Supabase se necessario"""
        if category not in self.CATEGORY_URL_TEMPLATES:
            print(f"❌ Categoria '{category}' non supportata")
            return None

        url_template = self.CATEGORY_URL_TEMPLATES[category]

        # Se l'URL contiene {giornata}, sostituiscilo con il numero da Supabase
        if '{giornata}' in url_template:
            giornata_number = self._get_current_giornata_from_supabase(category)
            if giornata_number:
                url = url_template.format(giornata=giornata_number)
                print(f"🎯 URL dinamico per {category}: {url}")
                return url
            else:
                # Fallback al numero 3 se non trovo nulla
                url = url_template.format(giornata='3')
                print(f"⚠️ Fallback per {category}: {url}")
                return url
        else:
            return url_template

    def scrape_category_results(self, category):
        """Scrapa risultati per una categoria specifica"""
        url = self._build_category_url(category)
        if not url:
            return None

        expected_opponents = self.EXPECTED_OPPONENTS.get(category, [])

        try:
            print(f"🌐 Caricamento: {url}")
            self.driver.get(url)

            # Attesa intelligente per la tabella risultati (più veloce)
            try:
                print("⏱️ Attesa caricamento tabella risultati...")
                WebDriverWait(self.driver, 6).until(
                    EC.presence_of_element_located((By.CSS_SELECTOR, "table.table-results"))
                )
                print("✅ Tabella risultati caricata")
            except:
                # Fallback: attesa generica più breve
                print("⚠️ Fallback: attesa generica...")
                WebDriverWait(self.driver, 3).until(
                    EC.presence_of_element_located((By.TAG_NAME, "body"))
                )
                time.sleep(1)  # Ridotto da 2 a 1 secondo

            # Cerca Aurora Seriate nella pagina (più specifico)
            page_text = self.driver.page_source.lower()
            if 'aurora seriate' not in page_text and 'aurora' not in page_text:
                print("❌ Aurora Seriate non trovata nella pagina")
                return None

            print("✅ Aurora Seriate trovata nella pagina")

            # Nuovo approccio: usare Selenium per trovare le partite nella tabella
            try:
                # Prima verifica se stiamo guardando la giornata corrente
                current_matchday_info = self._get_current_matchday_info()
                print(f"📅 Info giornata corrente: {current_matchday_info}")

                # Trova tutte le righe della tabella dei risultati
                match_rows = self.driver.find_elements(By.CSS_SELECTOR, "table.table-results tr.match")
                print(f"🔍 Trovate {len(match_rows)} partite nella tabella")

                # Mostra tutte le partite della giornata prima di cercare Aurora
                self._show_all_matches_in_matchday(match_rows)

                for i, row in enumerate(match_rows):
                    # Non stampare più "Analizzando partita" per ridurre noise
                    pass

                    # Trova elementi home e away team
                    home_team_elem = row.find_element(By.CSS_SELECTOR, "td.team.home")
                    away_team_elem = row.find_element(By.CSS_SELECTOR, "td.team.away")

                    # Estrai nomi delle squadre
                    home_team_name = home_team_elem.find_element(By.CSS_SELECTOR, "a.team-name").text.strip()
                    away_team_name = away_team_elem.find_element(By.CSS_SELECTOR, "a.team-name").text.strip()

                    print(f"🐛 Partita: {home_team_name} vs {away_team_name}")

                    # Controlla se una delle squadre è Aurora Seriate (più specifico)
                    aurora_home = 'aurora seriate' in home_team_name.lower() or 'aurora' in home_team_name.lower()
                    aurora_away = 'aurora seriate' in away_team_name.lower() or 'aurora' in away_team_name.lower()

                    if aurora_home or aurora_away:
                        print(f"🎯 Aurora trovata! Casa: {aurora_home}, Ospite: {aurora_away}")

                        # Estrai punteggi dagli elementi span.goal
                        try:
                            home_score_elem = home_team_elem.find_element(By.CSS_SELECTOR, "span.goal")
                            away_score_elem = away_team_elem.find_element(By.CSS_SELECTOR, "span.goal")

                            home_score = int(home_score_elem.text.strip())
                            away_score = int(away_score_elem.text.strip())

                            print(f"🎯 Punteggi trovati: {home_team_name} {home_score} - {away_score} {away_team_name}")

                            # Valida punteggi realistici
                            if home_score > 20 or away_score > 20:
                                print(f"⚠️ Punteggi troppo alti, probabilmente sbagliati: {home_score}-{away_score}")
                                continue

                            # Ora scarica anche le posizioni in classifica
                            print(f"🏆 Scaricando classifica per {category}...")
                            standings = self.scrape_category_standings(category)

                            home_position = None
                            away_position = None

                            if standings:
                                # Cerca le posizioni delle squadre
                                home_team_lower = home_team_name.lower()
                                away_team_lower = away_team_name.lower()

                                for team_key, team_data in standings.items():
                                    # Match più flessibile per i nomi delle squadre
                                    if (team_key in home_team_lower or
                                        any(word in team_key for word in home_team_lower.split()) or
                                        any(word in home_team_lower for word in team_key.split())):
                                        home_position = team_data['position']
                                        print(f"📊 {home_team_name} trovata in classifica: {home_position}° posto")

                                    if (team_key in away_team_lower or
                                        any(word in team_key for word in away_team_lower.split()) or
                                        any(word in away_team_lower for word in team_key.split())):
                                        away_position = team_data['position']
                                        print(f"📊 {away_team_name} trovata in classifica: {away_position}° posto")

                            result = {
                                "homeTeam": home_team_name,
                                "awayTeam": away_team_name,
                                "homeScore": home_score,
                                "awayScore": away_score,
                                "homePosition": home_position,
                                "awayPosition": away_position,
                                "category": category,
                                "championship": self._get_championship_name(category)
                            }

                            print(f"✅ Risultato COMPLETO trovato: {result['homeTeam']} ({home_position}°) {result['homeScore']}-{result['awayScore']} ({away_position}°) {result['awayTeam']}")
                            return result

                        except Exception as score_error:
                            print(f"🐛 Errore estrazione punteggi: {score_error}")
                            # Potrebbe essere una partita non ancora giocata o senza punteggio
                            continue
                    else:
                        print(f"🐛 Nessuna Aurora in questa partita")

            except Exception as table_error:
                print(f"❌ Errore nell'analisi della tabella: {table_error}")
                return None

            print(f"❌ Nessun risultato Aurora trovato per {category}")
            return None

        except TimeoutException:
            print("❌ Timeout caricamento pagina")
            return None
        except Exception as e:
            print(f"❌ Errore scraping: {e}")
            return None

    def _get_current_matchday_info(self):
        """Estrae informazioni sulla giornata corrente dalla pagina"""
        try:
            # Cerca elementi che indicano la giornata corrente
            matchday_elements = self.driver.find_elements(By.CSS_SELECTOR, "h1, h2, h3, .title, .matchday")
            for elem in matchday_elements:
                text = elem.text.lower()
                if 'giornata' in text or 'risultati' in text:
                    return text.strip()

            # Fallback: cerca nella URL
            current_url = self.driver.current_url
            if 'giornata' in current_url.lower():
                import re
                match = re.search(r'giornata(\d+)', current_url.lower())
                if match:
                    return f"Giornata {match.group(1)}"

            return "Giornata corrente"
        except Exception as e:
            print(f"⚠️ Errore nel recupero info giornata: {e}")
            return "Giornata sconosciuta"

    def _show_all_matches_in_matchday(self, match_rows):
        """Mostra tutte le partite della giornata prima di cercare Aurora"""
        try:
            import logging
            logger = logging.getLogger(__name__)

            logger.info("\n" + "="*60)
            logger.info("📋 TUTTE LE PARTITE DELLA GIORNATA:")
            logger.info("="*60)

            for i, row in enumerate(match_rows, 1):
                try:
                    # Trova elementi home e away team
                    home_team_elem = row.find_element(By.CSS_SELECTOR, "td.team.home")
                    away_team_elem = row.find_element(By.CSS_SELECTOR, "td.team.away")

                    # Estrai nomi delle squadre
                    home_team_name = home_team_elem.find_element(By.CSS_SELECTOR, "a.team-name").text.strip()
                    away_team_name = away_team_elem.find_element(By.CSS_SELECTOR, "a.team-name").text.strip()

                    # Prova a estrarre i punteggi
                    try:
                        home_score_elem = home_team_elem.find_element(By.CSS_SELECTOR, "span.goal")
                        away_score_elem = away_team_elem.find_element(By.CSS_SELECTOR, "span.goal")
                        home_score = home_score_elem.text.strip()
                        away_score = away_score_elem.text.strip()

                        # Controlla se Aurora è in questa partita
                        aurora_match = 'aurora' in home_team_name.lower() or 'aurora' in away_team_name.lower()
                        prefix = "🎯" if aurora_match else "⚽"

                        logger.info(f"{prefix} {i:2d}. {home_team_name} {home_score}-{away_score} {away_team_name}")
                    except:
                        # Partita senza punteggio (non ancora giocata)
                        aurora_match = 'aurora' in home_team_name.lower() or 'aurora' in away_team_name.lower()
                        prefix = "🎯" if aurora_match else "📅"
                        logger.info(f"{prefix} {i:2d}. {home_team_name} vs {away_team_name} (da giocare)")

                except Exception as match_error:
                    logger.info(f"⚠️ {i:2d}. Errore lettura partita: {match_error}")

            logger.info("="*60)
            logger.info("🔍 Ora cerco specificamente la partita di Aurora...")
            logger.info("="*60 + "\n")

        except Exception as e:
            print(f"⚠️ Errore nella visualizzazione partite: {e}")

    def _get_championship_name(self, category):
        """Ritorna il nome completo del campionato"""
        championship_names = {
            'PROMOZIONE': 'Promozione Girone A',
            'U21': 'Under21 Girone D',
            'U19': 'Juniores Elite U19 Girone C',
            'U18': 'Allievi Regionali U18 Girone D',
            'U17': 'Allievi Regionali U17 Girone D',
            'U16': 'Allievi Provinciali U16 Girone D Bergamo',
            'U15': 'Giovanissimi Provinciali U15 Girone C Bergamo',
            'U14': 'Giovanissimi Provinciali U14 Girone C Bergamo',
        }
        return championship_names.get(category, f'Campionato {category}')

    def scrape_promozione_results(self):
        """Backward compatibility per Promozione"""
        return self.scrape_category_results('PROMOZIONE')

    def scrape_all_aurora_results(self):
        """
        Nuovo metodo: cerca TUTTI i risultati di Aurora Seriate del giorno
        corrente su tuttocampo.it usando la ricerca generale
        Invece di cercare per categoria, fa una ricerca diretta per "AURORA SERIATE"
        """
        print("\n🎯 SCRAPING TUTTI I RISULTATI AURORA DEL GIORNO")
        print("=" * 60)

        all_results = []

        # Lista delle categorie agonistiche da controllare
        categories_to_check = ['PROMOZIONE', 'U21', 'U19', 'U18', 'U17', 'U16', 'U15', 'U14']

        for category in categories_to_check:
            try:
                print(f"\n🔍 Controllo categoria {category}...")
                result = self.scrape_category_results(category)

                if result:
                    print(f"✅ Trovato risultato {category}: {result['homeTeam']} {result['homeScore']}-{result['awayScore']} {result['awayTeam']}")
                    all_results.append(result)
                else:
                    print(f"⭕ Nessun risultato trovato per {category}")

                # Piccola pausa tra le categorie
                time.sleep(1)

            except Exception as e:
                print(f"❌ Errore scraping {category}: {e}")
                continue

        print(f"\n🎯 RIEPILOGO: Trovati {len(all_results)} risultati Aurora per oggi")
        for i, result in enumerate(all_results, 1):
            print(f"  {i}. {result['homeTeam']} {result['homeScore']}-{result['awayScore']} {result['awayTeam']} ({result['category']})")

        return all_results

    def scrape_category_standings(self, category):
        """Scrapa la classifica per una categoria specifica con debug migliorato"""
        print(f"🏆 ENHANCED DEBUG: Starting standings scraping for {category}")
        sys.stdout.flush()  # Force flush to see output immediately
        base_url = self._build_category_url(category)
        if not base_url:
            print(f"❌ Non riesco a costruire URL per {category}")
            return {}

        print(f"🌐 URL base: {base_url}")

        # Prova diversi URL per la classifica con pattern tuttocampo.it
        urls_to_try = [
            # Pattern principale: sostituisci /Risultati con /Classifica
            base_url.replace('/Risultati', '/Classifica'),
            # Pattern alternativo: prova pagina principale senza /Risultati
            base_url.replace('/Risultati', ''),
            # Pattern specifico: aggiungi /Classifica alla fine del girone
            base_url.replace('/Risultati', '/Classifica').replace('/Classifica/Classifica', '/Classifica'),
            # Prova URL senza modifiche (a volte la classifica è nella stessa pagina)
            base_url,
            # Pattern tuttocampo: prova con /Classifica diretta dopo girone
            base_url.replace('GironeA/Risultati', 'GironeA/Classifica'),
            base_url.replace('GironeB/Risultati', 'GironeB/Classifica'),
            base_url.replace('GironeC/Risultati', 'GironeC/Classifica'),
            base_url.replace('GironeD/Risultati', 'GironeD/Classifica'),
        ]

        # Rimuovi duplicati mantenendo l'ordine
        urls_to_try = list(dict.fromkeys(urls_to_try))

        print(f"🔍 Proverò {len(urls_to_try)} URL diversi per la classifica:")
        for i, url in enumerate(urls_to_try):
            print(f"  {i+1}. {url}")

        for i, standings_url in enumerate(urls_to_try):
            try:
                print(f"\n🏆 Tentativo {i+1}/{len(urls_to_try)}: {standings_url}")
                self.driver.get(standings_url)

                # Verifica se la pagina si è caricata correttamente
                page_title = self.driver.title
                print(f"📄 Titolo pagina: {page_title}")

                # Attesa caricamento pagina più lunga per debug
                time.sleep(4)

                # Debug: stampa URL corrente dopo eventuali redirect
                current_url = self.driver.current_url
                print(f"🌐 URL effettivo dopo redirect: {current_url}")

                # Cerca la classifica con selettori migliorati
                standings_data = self._extract_standings_from_page()
                if standings_data:
                    print(f"✅ SUCCESSO! Classifica trovata su: {standings_url}")
                    print(f"📊 Trovate {len(standings_data)} squadre in classifica")
                    # Stampa prime 3 squadre per verifica
                    for j, (team, data) in enumerate(list(standings_data.items())[:3]):
                        print(f"  {data['position']}. {team} - {data['points']} pt")
                    return standings_data
                else:
                    print(f"⚠️ Nessuna classifica trovata su: {standings_url}")
            except Exception as e:
                print(f"❌ Errore su {standings_url}: {str(e)}")
                continue

        print("❌ FALLIMENTO: Nessuna classifica trovata in tutti gli URL tentati")
        return {}

    def _extract_standings_from_page(self):
        """Estrae la classifica dalla pagina corrente"""
        try:

            # Cerca la tabella della classifica con selettori più ampi
            standings_table = None
            table_selectors = [
                # Selettori specifici per tuttocampo.it
                "table.table-striped",
                "table.table-condensed",
                "table[summary*='classifica']",
                "table[summary*='Classifica']",
                ".table-responsive table",
                ".classifica table",
                ".standings table",
                # Selettori generici
                "table.table-standings",
                "table.standings-table",
                "table.classifica",
                "table",
                # Cercare tabelle che contengono teste con "pos", "squadra", "punti"
                "table:has(th:contains('Pos'))",
                "table:has(th:contains('Squadra'))",
                "table:has(th:contains('Pt'))",
            ]

            # Debug: stampa tutte le tabelle presenti
            all_tables = self.driver.find_elements(By.TAG_NAME, "table")
            print(f"🔍 Trovate {len(all_tables)} tabelle nella pagina")

            for i, table in enumerate(all_tables):
                try:
                    # Stampa informazioni sulla tabella
                    class_attr = table.get_attribute("class") or "no-class"
                    summary_attr = table.get_attribute("summary") or "no-summary"
                    print(f"  Tabella {i}: class='{class_attr}', summary='{summary_attr}'")

                    # Controlla se ha header con colonne tipiche della classifica
                    headers = table.find_elements(By.TAG_NAME, "th")
                    if headers:
                        header_texts = [h.text.strip().lower() for h in headers]
                        print(f"    Headers: {header_texts}")

                        # Se contiene colonne tipiche della classifica, usala
                        if any(keyword in ' '.join(header_texts) for keyword in ['pos', 'squadra', 'pt', 'punti', 'classifica']):
                            print(f"✅ Tabella {i} sembra essere una classifica!")
                            standings_table = table
                            break
                except Exception as e:
                    print(f"    Errore analizzando tabella {i}: {e}")

            # Fallback ai selettori originali
            if not standings_table:
                for selector in table_selectors:
                    try:
                        standings_table = self.driver.find_element(By.CSS_SELECTOR, selector)
                        print(f"✅ Trovata tabella con selettore: {selector}")
                        break
                    except:
                        continue

            if not standings_table:
                print("❌ Nessuna tabella classifica trovata")
                return {}

            print("✅ Tabella classifica trovata")

            # Estrai righe della classifica
            rows = standings_table.find_elements(By.TAG_NAME, "tr")
            standings = {}

            print(f"🔍 Trovate {len(rows)} righe nella tabella classifica")

            # Skip header row(s)
            for row_index, row in enumerate(rows[1:], 1):  # Skip prima riga (header)
                try:
                    cells = row.find_elements(By.TAG_NAME, "td")
                    print(f"  Riga {row_index}: {len(cells)} celle")

                    # Debug: stampa contenuto di tutte le celle
                    cell_contents = []
                    for i, cell in enumerate(cells):
                        content = cell.text.strip()
                        cell_contents.append(f"{i}:'{content}'")
                    print(f"    Contenuto: {' | '.join(cell_contents)}")

                    if len(cells) < 3:  # Deve avere almeno posizione, squadra, punti
                        print(f"    ⚠️ Riga saltata: troppe poche celle ({len(cells)} < 3)")
                        continue

                    # La posizione è implicita nell'ordine delle righe (1° = riga 1, 2° = riga 2, etc.)
                    position = row_index

                    # Nome squadra è nella cella 2 (come mostrato dal debug)
                    team_name = cells[2].text.strip() if len(cells) > 2 else ""

                    if not team_name:
                        continue

                    # Parsing completo delle statistiche della classifica
                    # Tipica struttura tuttocampo: Pos | Logo | Squadra | Pt | G | V | P | S | GF | GS | DR
                    points = 0
                    played = 0
                    wins = 0
                    draws = 0
                    losses = 0
                    goals_for = 0
                    goals_against = 0

                    # Estrazione sicura dei dati numerici
                    if len(cells) > 3:
                        points = int(cells[3].text.strip()) if cells[3].text.strip().isdigit() else 0
                    if len(cells) > 4:
                        played = int(cells[4].text.strip()) if cells[4].text.strip().isdigit() else 0
                    if len(cells) > 5:
                        wins = int(cells[5].text.strip()) if cells[5].text.strip().isdigit() else 0
                    if len(cells) > 6:
                        draws = int(cells[6].text.strip()) if cells[6].text.strip().isdigit() else 0
                    if len(cells) > 7:
                        losses = int(cells[7].text.strip()) if cells[7].text.strip().isdigit() else 0
                    if len(cells) > 8:
                        goals_for = int(cells[8].text.strip()) if cells[8].text.strip().isdigit() else 0
                    if len(cells) > 9:
                        goals_against = int(cells[9].text.strip()) if cells[9].text.strip().isdigit() else 0

                    standings[team_name.lower()] = {
                        'position': position,
                        'points': points,
                        'played': played,
                        'wins': wins,
                        'draws': draws,
                        'losses': losses,
                        'goals_for': goals_for,
                        'goals_against': goals_against,
                        'team_name': team_name
                    }

                    print(f"📊 {position}° {team_name}: {points}pt G{played} V{wins} P{draws} S{losses} GF{goals_for} GS{goals_against}")

                except Exception as row_error:
                    print(f"🐛 Errore parsing riga: {row_error}")
                    continue

            print(f"✅ Classifica estratta: {len(standings)} squadre")
            return standings

        except Exception as e:
            print(f"❌ Errore scraping classifica {category}: {e}")
            return {}

def main():
    """Funzione principale"""
    # Parsing argumenti
    category = 'PROMOZIONE'  # Default
    headless = True

    for i, arg in enumerate(sys.argv[1:], 1):
        if arg == "--visible":
            headless = False
        elif arg.startswith("--category="):
            category = arg.split("=")[1].upper()
        elif arg in TuttocampoSeleniumScraper.CATEGORY_URL_TEMPLATES.keys():
            category = arg

    print(f"🎯 Scraping categoria: {category}")

    scraper = TuttocampoSeleniumScraper(headless=headless)

    try:
        if not scraper.start():
            print("❌ Impossibile avviare Chrome")
            return

        # Test per tutte le categorie se nessuna specificata
        if len(sys.argv) > 1 and sys.argv[1] == "--all":
            print("🔍 Testing tutte le categorie...")
            for cat in scraper.CATEGORY_URL_TEMPLATES.keys():
                print(f"\n--- Testando {cat} ---")
                result = scraper.scrape_category_results(cat)
                if result:
                    print(f"✅ {cat}: {result['homeTeam']} {result['homeScore']}-{result['awayScore']} {result['awayTeam']}")
                else:
                    print(f"❌ {cat}: Nessun risultato trovato")
        else:
            # Scraping singola categoria
            result = scraper.scrape_category_results(category)

            if result:
                print("\n🎯 RISULTATO FINALE:")
                print(json.dumps(result, indent=2, ensure_ascii=False))
            else:
                print(f"\n❌ Nessun risultato trovato per {category}")

    finally:
        scraper.stop()

if __name__ == "__main__":
    main()