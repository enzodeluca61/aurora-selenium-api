#!/usr/bin/env python3
"""
API Server per Selenium Scraping - Aurora Seriate 1967
Espone le funzioni di scraping Selenium come API REST per l'app Flutter Android
"""

from flask import Flask, jsonify, request
from flask_cors import CORS
import threading
import time
import logging
# Import Selenium scraper
try:
    from selenium_scraper import TuttocampoSeleniumScraper
    SELENIUM_AVAILABLE = True
except ImportError:
    SELENIUM_AVAILABLE = False

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)  # Permette chiamate da Flutter app

# Cache ottimizzata per prestazioni
scraping_cache = {}
CACHE_DURATION = 1800  # 30 minuti (le classifiche cambiano lentamente)
STANDINGS_CACHE_DURATION = 3600  # 1 ora per le classifiche (ancora più stabili)
FAST_CACHE_DURATION = 30  # 30 secondi per errori temporanei

class ScrapingAPIServer:
    def __init__(self):
        # Pool di browser per riutilizzo (più veloce)
        self.scraper_pool = []
        self.pool_lock = threading.Lock()
        self.max_pool_size = 2  # Max 2 browser simultanei

        # Lock principale per coordinamento
        self.scraper_lock = threading.Lock()

        # Inizializza pool di browser
        self._initialize_scraper_pool()

    def _initialize_scraper_pool(self):
        """Inizializza un pool di browser riutilizzabili"""
        if not SELENIUM_AVAILABLE:
            print("🚧 Selenium non disponibile - modalità fallback attivata")
            return

        print("🏊‍♂️ Inizializzazione pool di browser per prestazioni ottimali...")
        try:
            # Crea il primo browser
            scraper = TuttocampoSeleniumScraper(headless=True)
            if scraper.start():
                self.scraper_pool.append(scraper)
                print("✅ Browser nel pool: 1")
            else:
                print("⚠️ Non è stato possibile inizializzare il browser pool")
        except Exception as e:
            print(f"⚠️ Errore inizializzazione pool: {e}")

    def _get_scraper_from_pool(self):
        """Ottieni un browser dal pool o creane uno nuovo"""
        with self.pool_lock:
            if self.scraper_pool:
                return self.scraper_pool.pop()
            else:
                # Crea nuovo browser se pool vuoto
                print("🏁 Creazione browser temporaneo...")
                scraper = TuttocampoSeleniumScraper(headless=True)
                return scraper

    def _return_scraper_to_pool(self, scraper):
        """Restituisce un browser al pool per riutilizzo"""
        with self.pool_lock:
            if len(self.scraper_pool) < self.max_pool_size:
                self.scraper_pool.append(scraper)
            else:
                # Pool pieno, chiudi browser
                try:
                    scraper.stop()
                except:
                    pass

    def get_cached_result(self, category):
        """Controlla se abbiamo un risultato in cache ancora valido"""
        if category in scraping_cache:
            cached_data, timestamp = scraping_cache[category]
            if time.time() - timestamp < CACHE_DURATION:
                logger.info(f"Returning cached result for {category}")
                return cached_data
        return None

    def set_cache(self, category, data):
        """Salva il risultato in cache"""
        scraping_cache[category] = (data, time.time())

    def scrape_category_safe(self, category):
        """Scraping ottimizzato con pool di browser riutilizzabili"""
        start_time = time.time()

        try:
            # Controlla cache prima
            cached_result = self.get_cached_result(category)
            if cached_result:
                logger.info(f"Cache hit for {category} (0.00s)")
                return cached_result

            # Scraping con timeout ridotto
            if not self.scraper_lock.acquire(timeout=3):
                logger.warning(f"Could not acquire lock for {category} within 3 seconds")
                return {"error": "Server busy, try again later"}

            scraper = None
            try:
                logger.info(f"Starting optimized scraping for {category}")

                # Ottieni browser dal pool
                scraper = self._get_scraper_from_pool()

                # Se non è già avviato, avvialo
                if not scraper.driver:
                    if not scraper.start():
                        return {"error": "Failed to start Chrome browser"}

                result = scraper.scrape_category_results(category)

                if result:
                    # Converte il risultato in formato JSON serializable
                    json_result = {
                        "homeTeam": result["homeTeam"],
                        "awayTeam": result["awayTeam"],
                        "homeScore": result["homeScore"],
                        "awayScore": result["awayScore"],
                        "category": result["category"],
                        "championship": result["championship"]
                    }

                    # Salva in cache
                    self.set_cache(category, json_result)

                    elapsed = time.time() - start_time
                    logger.info(f"⚡ Fast scraping {category}: {json_result['homeTeam']} {json_result['homeScore']}-{json_result['awayScore']} {json_result['awayTeam']} ({elapsed:.2f}s)")
                    return json_result
                else:
                    error_msg = f"No results found for {category}"
                    logger.warning(error_msg)
                    return {"error": error_msg}

            finally:
                # Restituisci browser al pool invece di chiuderlo
                if scraper:
                    self._return_scraper_to_pool(scraper)
                self.scraper_lock.release()

        except Exception as e:
            elapsed = time.time() - start_time
            error_msg = f"Scraping error for {category}: {str(e)} ({elapsed:.2f}s)"
            logger.error(error_msg)
            return {"error": error_msg}

# Istanza globale del server
scraping_server = ScrapingAPIServer()

@app.route('/', methods=['GET'])
def root():
    """Root endpoint"""
    return jsonify({
        "service": "Aurora Selenium API",
        "status": "running",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "scrape_category": "/scrape/<category>",
            "scrape_all": "/scrape/all",
            "aurora_results": "/scrape/aurora-results",
            "standings": "/standings/<category>",
            "cache_status": "/cache/status",
            "cache_clear": "/cache/clear"
        }
    })

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "ok", "service": "selenium-api-server"})

@app.route('/scrape/<category>', methods=['GET'])
def scrape_category(category):
    """
    Endpoint principale per scraping
    GET /scrape/PROMOZIONE
    GET /scrape/U17
    etc.
    """
    try:
        category = category.upper()
        logger.info(f"API request for category: {category}")

        # Lista delle categorie supportate
        supported_categories = ['PROMOZIONE', 'U21', 'U19', 'U18', 'U17', 'U16', 'U15', 'U14']

        if category not in supported_categories:
            return jsonify({
                "error": f"Category {category} not supported. Supported: {supported_categories}"
            }), 400

        # Esegui scraping
        result = scraping_server.scrape_category_safe(category)

        if "error" in result:
            return jsonify(result), 500
        else:
            return jsonify({
                "success": True,
                "data": result
            })

    except Exception as e:
        logger.error(f"API error: {str(e)}")
        return jsonify({"error": f"Server error: {str(e)}"}), 500

@app.route('/scrape/all', methods=['GET'])
def scrape_all_categories():
    """
    Endpoint per scraping di tutte le categorie
    GET /scrape/all
    """
    try:
        logger.info("API request for all categories")
        categories = ['PROMOZIONE', 'U21', 'U19', 'U18', 'U17', 'U16', 'U15', 'U14']

        results = {}
        for category in categories:
            logger.info(f"Scraping {category}...")
            result = scraping_server.scrape_category_safe(category)
            results[category] = result

            # Piccola pausa tra categorie
            time.sleep(2)

        return jsonify({
            "success": True,
            "data": results
        })

    except Exception as e:
        logger.error(f"API error: {str(e)}")
        return jsonify({"error": f"Server error: {str(e)}"}), 500

@app.route('/cache/status', methods=['GET'])
def cache_status():
    """Endpoint per controllare lo stato della cache"""
    cache_info = {}
    current_time = time.time()

    for category, (data, timestamp) in scraping_cache.items():
        age_seconds = current_time - timestamp
        # Determina la durata cache appropriata
        cache_duration = STANDINGS_CACHE_DURATION if category.startswith("standings_") else CACHE_DURATION
        cache_info[category] = {
            "age_seconds": round(age_seconds, 1),
            "is_valid": age_seconds < cache_duration,
            "cache_duration_used": cache_duration,
            "data": data
        }

    return jsonify({
        "results_cache_duration": CACHE_DURATION,
        "standings_cache_duration": STANDINGS_CACHE_DURATION,
        "cache_info": cache_info
    })

@app.route('/cache/clear', methods=['POST'])
def clear_cache():
    """Endpoint per pulire la cache"""
    global scraping_cache
    old_count = len(scraping_cache)
    scraping_cache.clear()

    return jsonify({
        "success": True,
        "message": f"Cache cleared. Removed {old_count} entries."
    })

@app.route('/standings/<category>', methods=['GET'])
def scrape_standings(category):
    """Endpoint per scaricare la classifica di una categoria"""
    category = category.upper()
    cache_key = f"standings_{category}"

    # Controlla cache
    current_time = time.time()
    if cache_key in scraping_cache:
        cached_data, cache_time = scraping_cache[cache_key]
        if current_time - cache_time < STANDINGS_CACHE_DURATION:
            logger.info(f"🏆 Returning cached standings for {category}")
            return jsonify({
                "success": True,
                "category": category,
                "standings": cached_data,
                "cached": True,
                "timestamp": cache_time
            })

    # Scraping classifica
    logger.info(f"🏆 Scraping standings for {category}")
    scraper = scraping_server._get_scraper_from_pool()

    if not scraper:
        return jsonify({
            "success": False,
            "error": "No scraper available",
            "category": category
        }), 500

    try:
        standings = scraper.scrape_category_standings(category)

        if standings:
            # Cache risultato
            scraping_cache[cache_key] = (standings, current_time)
            logger.info(f"✅ Standings scraped successfully for {category}: {len(standings)} teams")

            return jsonify({
                "success": True,
                "category": category,
                "standings": standings,
                "cached": False,
                "timestamp": current_time
            })
        else:
            # Cache errore temporaneo (durata più breve)
            scraping_cache[cache_key] = ({}, current_time - STANDINGS_CACHE_DURATION + FAST_CACHE_DURATION)
            logger.warning(f"⚠️ No standings found for {category}")

            return jsonify({
                "success": False,
                "error": "No standings found",
                "category": category
            }), 404

    except Exception as e:
        logger.error(f"❌ Error scraping standings for {category}: {e}")
        return jsonify({
            "success": False,
            "error": str(e),
            "category": category
        }), 500

    finally:
        scraping_server._return_scraper_to_pool(scraper)

@app.route('/update-standings/<category>', methods=['POST'])
def update_standings_for_matches(category):
    """Endpoint per aggiornare le posizioni in classifica per tutte le partite di una categoria"""
    category = category.upper()

    # Prima scarica la classifica
    logger.info(f"🏆 Downloading standings for {category}")
    scraper = scraping_server._get_scraper_from_pool()

    if not scraper:
        return jsonify({
            "success": False,
            "error": "No scraper available"
        }), 500

    try:
        standings = scraper.scrape_category_standings(category)

        if not standings:
            return jsonify({
                "success": False,
                "error": "Could not retrieve standings"
            }), 404

        # Ora aggiorna le posizioni nel database Supabase
        from supabase import create_client

        SUPABASE_URL = 'https://hkhuabfxjlcidlodbiru.supabase.co'
        SUPABASE_KEY = ('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
                       'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhraHVhYmZ4amxjaWRsb2RiaXJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTYwNTM2MjAsImV4cCI6MjA3MTYyOTYyMH0.'
                       'ywg26EFefan4H1sPySmrWS0ndh6gPjOyjfqCIUQ67Ws')

        supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

        updated_matches = 0

        # Aggiorna le partite nella tabella matches
        try:
            matches_response = supabase.table('matches').select('*').execute()

            for match in matches_response.data:
                # Usa i nomi corretti dei campi nella tabella matches
                home_team = match.get('aurora_team', '').lower() if match.get('is_home', True) else match.get('opponent', '').lower()
                away_team = match.get('opponent', '').lower() if match.get('is_home', True) else match.get('aurora_team', '').lower()

                home_position = None
                away_position = None

                # Cerca le posizioni nelle standings
                for team_key, team_data in standings.items():
                    if team_key in home_team or any(word in team_key for word in home_team.split()):
                        home_position = team_data['position']
                    if team_key in away_team or any(word in team_key for word in away_team.split()):
                        away_position = team_data['position']

                # Aggiorna solo se abbiamo trovato almeno una posizione
                if home_position or away_position:
                    update_data = {}
                    if home_position:
                        update_data['home_position'] = home_position
                    if away_position:
                        update_data['away_position'] = away_position

                    supabase.table('matches').update(update_data).eq('id', match['id']).execute()
                    updated_matches += 1
                    logger.info(f"Updated match {match['id']}: {home_team} ({home_position}) vs {away_team} ({away_position})")

        except Exception as db_error:
            logger.error(f"Database update error: {db_error}")
            return jsonify({
                "success": False,
                "error": f"Database update failed: {str(db_error)}"
            }), 500

        return jsonify({
            "success": True,
            "category": category,
            "standings_found": len(standings),
            "matches_updated": updated_matches,
            "message": f"Updated {updated_matches} matches with standings data"
        })

    except Exception as e:
        logger.error(f"❌ Error updating standings for {category}: {e}")
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

    finally:
        scraping_server._return_scraper_to_pool(scraper)

@app.route('/scrape/aurora-results', methods=['GET'])
def scrape_aurora_results():
    """
    Endpoint per scaricare TUTTI i risultati di Aurora Seriate del giorno
    Cerca "AURORA SERIATE" invece delle categorie specifiche
    """
    try:
        logger.info("🎯 API request for ALL Aurora results")

        # Verifica che Selenium sia disponibile
        if not SELENIUM_AVAILABLE:
            logger.error("🚧 Selenium not available - cannot proceed")
            return jsonify({
                "success": False,
                "error": "Selenium not available in this environment"
            }), 500

        # Usa la cache per i risultati Aurora
        cache_key = "aurora_all_results"
        current_time = time.time()

        # Controlla cache
        if cache_key in scraping_cache:
            cached_data, cache_time = scraping_cache[cache_key]
            if current_time - cache_time < CACHE_DURATION:
                logger.info(f"🎯 Returning cached Aurora results")
                return jsonify({
                    "success": True,
                    "data": cached_data,
                    "cached": True,
                    "timestamp": cache_time
                })

        # Esegui scraping per Aurora Seriate
        scraper = scraping_server._get_scraper_from_pool()

        if not scraper:
            return jsonify({
                "success": False,
                "error": "No scraper available"
            }), 500

        try:
            # Se non è già avviato, avvialo
            if not scraper.driver:
                if not scraper.start():
                    return jsonify({
                        "success": False,
                        "error": "Failed to start Chrome browser"
                    }), 500

            # Cerca TUTTI i risultati di Aurora Seriate del giorno
            results = scraper.scrape_all_aurora_results()

            if results:
                # Salva in cache
                scraping_cache[cache_key] = (results, current_time)

                logger.info(f"✅ Found {len(results)} Aurora results for the day")

                return jsonify({
                    "success": True,
                    "data": results,
                    "cached": False,
                    "timestamp": current_time
                })
            else:
                logger.warning("❌ No Aurora results found for today")
                return jsonify({
                    "success": False,
                    "error": "No Aurora results found for today"
                }), 404

        finally:
            scraping_server._return_scraper_to_pool(scraper)

    except Exception as e:
        logger.error(f"❌ Error scraping Aurora results: {e}")
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

if __name__ == '__main__':
    import os
    port = int(os.environ.get("PORT", 5001))

    logger.info("🚀 Starting Selenium API Server for Aurora Seriate 1967")

    if SELENIUM_AVAILABLE:
        logger.info("✅ Selenium available - full functionality enabled")
    else:
        logger.warning("⚠️ Selenium not available - limited functionality")

    logger.info("📱 Ready to serve Flutter Android app requests")
    logger.info(f"🌐 Server will run on http://0.0.0.0:{port}")
    logger.info("📋 Available endpoints:")
    logger.info("   GET /health - Health check")
    logger.info("   GET /scrape/<category> - Scrape specific category")
    logger.info("   GET /scrape/all - Scrape all categories")
    logger.info("   GET /scrape/aurora-results - Scrape ALL Aurora results for today")
    logger.info("   GET /cache/status - Check cache status")
    logger.info("   POST /cache/clear - Clear cache")

    # Avvia il server Flask
    app.run(host='0.0.0.0', port=port, debug=False, threaded=True)