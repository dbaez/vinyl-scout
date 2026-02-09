import 'package:flutter/material.dart';

/// Localizaciones de la aplicación VinylScout
/// Soporta: Español, Inglés, Francés, Italiano, Alemán
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    // ==================== ESPAÑOL ====================
    'es': {
      // App
      'appTitle': 'VinylScout',
      'appSubtitle': 'Tu colección de vinilos, organizada',
      'continueWithGoogle': 'Continuar con Google',
      'discoverYourCollection': 'Descubre, organiza y disfruta tu colección',
      
      // Navigation
      'collection': 'Colección',
      'shelves': 'Estanterías',
      'scan': 'Escanear',
      'playlists': 'Playlists',
      'profile': 'Perfil',
      
      // Shelves
      'myShelves': 'Mis Estanterías',
      'addShelf': 'Añadir Estantería',
      'shelfName': 'Nombre de la estantería',
      'takePhoto': 'Tomar foto',
      'selectPhoto': 'Seleccionar foto',
      'noShelvesYet': 'Aún no tienes estanterías',
      'createFirstShelf': 'Crea tu primera estantería para empezar',
      'deleteShelf': 'Eliminar estantería',
      'confirmDeleteShelf': '¿Estás seguro de que quieres eliminar',
      'editName': 'Editar nombre',
      'showHideZones': 'Mostrar/ocultar zonas',
      'viewFullImage': 'Ver imagen completa',
      'resetZoom': 'Restablecer zoom',
      
      // Zones
      'zones': 'Zonas',
      'zone': 'Zona',
      'addZone': 'Añadir zona',
      'deleteZone': 'Eliminar zona',
      'confirmDeleteZone': '¿Estás seguro de que quieres eliminar la Zona',
      'noZonesDefined': 'Sin zonas definidas',
      'divideShelfIntoZones': 'Divide tu estantería en zonas para organizar mejor tus vinilos',
      'createFirstZone': 'Crear primera zona',
      'useButtonBelow': 'Usa el botón de abajo para empezar',
      'readyToDiscover': '¿Listo para descubrir tus tesoros?',
      'zoneHasAlbums': 'Esta zona tiene',
      'albumsAssociated': 'álbumes asociados',
      'albumAssociated': 'álbum asociado',
      'albumsWillNotBeDeleted': 'Los álbumes no se eliminarán, pero perderán su ubicación.',
      'deleteAnyway': 'Eliminar de todos modos',
      'zoneDeleted': 'Zona eliminada',
      'attention': '¡Atención!',
      
      // Albums
      'albums': 'Álbumes',
      'album': 'Álbum',
      'myCollection': 'Mi Colección',
      'searchAlbums': 'Buscar álbumes...',
      'addAlbum': 'Añadir álbum',
      'noAlbums': 'Sin álbumes',
      'artist': 'Artista',
      'title': 'Título',
      'year': 'Año',
      'genres': 'Géneros',
      'styles': 'Estilos',
      
      // Stats
      'created': 'Creada',
      'scanned': 'Escaneada',
      'lastScanned': 'Último escaneo',
      
      // Actions
      'save': 'Guardar',
      'cancel': 'Cancelar',
      'delete': 'Eliminar',
      'edit': 'Editar',
      'confirm': 'Confirmar',
      'close': 'Cerrar',
      'loading': 'Cargando...',
      'error': 'Error',
      'success': 'Éxito',
      'retry': 'Reintentar',
      
      // Profile
      'logout': 'Cerrar sesión',
      'linkDiscogs': 'Vincular con Discogs',
      'discogsLinked': 'Discogs vinculado',
      'syncCollection': 'Sincronizar colección',
      'settings': 'Configuración',
      'language': 'Idioma',
      'theme': 'Tema',
      'darkMode': 'Modo oscuro',
      'lightMode': 'Modo claro',
      'about': 'Acerca de',
      'version': 'Versión',
      'privacyPolicy': 'Política de privacidad',
      'termsOfService': 'Términos de servicio',
      
      // Messages
      'welcomeTo': 'Bienvenido a',
      'errorOccurred': 'Ha ocurrido un error',
      'tryAgain': 'Inténtalo de nuevo',
      'noResults': 'Sin resultados',
      'searchNoResults': 'No se encontraron resultados para tu búsqueda',
      
      // Scanner
      'scanner': 'Escáner',
      'scannerTitle': '¡Encuadra los lomos de tus vinilos aquí!',
      'scannerHint': 'Asegúrate de que la luz sea buena y los lomos se vean nítidos.',
      'readyForGemini': '¡Listo para Gemini...!',
      'takePhotoButton': '¡Tomar Foto!',
      'analyzing': 'Analizando...',
      'scannerTipLight': '¡No veo muy bien los lomos! ¿Puedes encender la luz?',
      'scannerTipCloser': '¡Acércate un poco más para ver mejor los títulos!',
      'scannerTipSteady': 'Mantén el móvil estable para una foto más nítida.',
      'scannerSuccess': '¡Perfecto! Foto capturada correctamente.',
      'cameraPermissionDenied': 'Se necesita permiso de cámara para escanear',
      'cameraNotAvailable': 'Cámara no disponible',
      'processingImage': 'Procesando imagen...',
      'sendingToGemini': 'Enviando a Gemini...',
      'scanZone': 'Escanear zona',
    },
    
    // ==================== ENGLISH ====================
    'en': {
      // App
      'appTitle': 'VinylScout',
      'appSubtitle': 'Your vinyl collection, organized',
      'continueWithGoogle': 'Continue with Google',
      'discoverYourCollection': 'Discover, organize and enjoy your collection',
      
      // Navigation
      'collection': 'Collection',
      'shelves': 'Shelves',
      'scan': 'Scan',
      'playlists': 'Playlists',
      'profile': 'Profile',
      
      // Shelves
      'myShelves': 'My Shelves',
      'addShelf': 'Add Shelf',
      'shelfName': 'Shelf name',
      'takePhoto': 'Take photo',
      'selectPhoto': 'Select photo',
      'noShelvesYet': 'No shelves yet',
      'createFirstShelf': 'Create your first shelf to get started',
      'deleteShelf': 'Delete shelf',
      'confirmDeleteShelf': 'Are you sure you want to delete',
      'editName': 'Edit name',
      'showHideZones': 'Show/hide zones',
      'viewFullImage': 'View full image',
      'resetZoom': 'Reset zoom',
      
      // Zones
      'zones': 'Zones',
      'zone': 'Zone',
      'addZone': 'Add zone',
      'deleteZone': 'Delete zone',
      'confirmDeleteZone': 'Are you sure you want to delete Zone',
      'noZonesDefined': 'No zones defined',
      'divideShelfIntoZones': 'Divide your shelf into zones to better organize your vinyls',
      'createFirstZone': 'Create first zone',
      'useButtonBelow': 'Use the button below to get started',
      'readyToDiscover': 'Ready to discover your treasures?',
      'zoneHasAlbums': 'This zone has',
      'albumsAssociated': 'albums associated',
      'albumAssociated': 'album associated',
      'albumsWillNotBeDeleted': 'The albums will not be deleted, but they will lose their location.',
      'deleteAnyway': 'Delete anyway',
      'zoneDeleted': 'Zone deleted',
      'attention': 'Attention!',
      
      // Albums
      'albums': 'Albums',
      'album': 'Album',
      'myCollection': 'My Collection',
      'searchAlbums': 'Search albums...',
      'addAlbum': 'Add album',
      'noAlbums': 'No albums',
      'artist': 'Artist',
      'title': 'Title',
      'year': 'Year',
      'genres': 'Genres',
      'styles': 'Styles',
      
      // Stats
      'created': 'Created',
      'scanned': 'Scanned',
      'lastScanned': 'Last scanned',
      
      // Actions
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'edit': 'Edit',
      'confirm': 'Confirm',
      'close': 'Close',
      'loading': 'Loading...',
      'error': 'Error',
      'success': 'Success',
      'retry': 'Retry',
      
      // Profile
      'logout': 'Log out',
      'linkDiscogs': 'Link with Discogs',
      'discogsLinked': 'Discogs linked',
      'syncCollection': 'Sync collection',
      'settings': 'Settings',
      'language': 'Language',
      'theme': 'Theme',
      'darkMode': 'Dark mode',
      'lightMode': 'Light mode',
      'about': 'About',
      'version': 'Version',
      'privacyPolicy': 'Privacy Policy',
      'termsOfService': 'Terms of Service',
      
      // Messages
      'welcomeTo': 'Welcome to',
      'errorOccurred': 'An error occurred',
      'tryAgain': 'Try again',
      'noResults': 'No results',
      'searchNoResults': 'No results found for your search',
      
      // Scanner
      'scanner': 'Scanner',
      'scannerTitle': 'Frame your vinyl spines here!',
      'scannerHint': 'Make sure the lighting is good and the spines are visible.',
      'readyForGemini': 'Ready for Gemini...!',
      'takePhotoButton': 'Take Photo!',
      'analyzing': 'Analyzing...',
      'scannerTipLight': "I can't see the spines well! Can you turn on the light?",
      'scannerTipCloser': 'Get a little closer to see the titles better!',
      'scannerTipSteady': 'Keep your phone steady for a sharper photo.',
      'scannerSuccess': 'Perfect! Photo captured successfully.',
      'cameraPermissionDenied': 'Camera permission is needed to scan',
      'cameraNotAvailable': 'Camera not available',
      'processingImage': 'Processing image...',
      'sendingToGemini': 'Sending to Gemini...',
      'scanZone': 'Scan zone',
    },
    
    // ==================== FRANÇAIS ====================
    'fr': {
      // App
      'appTitle': 'VinylScout',
      'appSubtitle': 'Votre collection de vinyles, organisée',
      'continueWithGoogle': 'Continuer avec Google',
      'discoverYourCollection': 'Découvrez, organisez et profitez de votre collection',
      
      // Navigation
      'collection': 'Collection',
      'shelves': 'Étagères',
      'scan': 'Scanner',
      'playlists': 'Playlists',
      'profile': 'Profil',
      
      // Shelves
      'myShelves': 'Mes Étagères',
      'addShelf': 'Ajouter une étagère',
      'shelfName': 'Nom de l\'étagère',
      'takePhoto': 'Prendre une photo',
      'selectPhoto': 'Sélectionner une photo',
      'noShelvesYet': 'Pas encore d\'étagères',
      'createFirstShelf': 'Créez votre première étagère pour commencer',
      'deleteShelf': 'Supprimer l\'étagère',
      'confirmDeleteShelf': 'Êtes-vous sûr de vouloir supprimer',
      'editName': 'Modifier le nom',
      'showHideZones': 'Afficher/masquer les zones',
      'viewFullImage': 'Voir l\'image complète',
      'resetZoom': 'Réinitialiser le zoom',
      
      // Zones
      'zones': 'Zones',
      'zone': 'Zone',
      'addZone': 'Ajouter une zone',
      'deleteZone': 'Supprimer la zone',
      'confirmDeleteZone': 'Êtes-vous sûr de vouloir supprimer la Zone',
      'noZonesDefined': 'Aucune zone définie',
      'divideShelfIntoZones': 'Divisez votre étagère en zones pour mieux organiser vos vinyles',
      'createFirstZone': 'Créer la première zone',
      'useButtonBelow': 'Utilisez le bouton ci-dessous pour commencer',
      'readyToDiscover': 'Prêt à découvrir vos trésors ?',
      'zoneHasAlbums': 'Cette zone contient',
      'albumsAssociated': 'albums associés',
      'albumAssociated': 'album associé',
      'albumsWillNotBeDeleted': 'Les albums ne seront pas supprimés, mais ils perdront leur emplacement.',
      'deleteAnyway': 'Supprimer quand même',
      'zoneDeleted': 'Zone supprimée',
      'attention': 'Attention !',
      
      // Albums
      'albums': 'Albums',
      'album': 'Album',
      'myCollection': 'Ma Collection',
      'searchAlbums': 'Rechercher des albums...',
      'addAlbum': 'Ajouter un album',
      'noAlbums': 'Aucun album',
      'artist': 'Artiste',
      'title': 'Titre',
      'year': 'Année',
      'genres': 'Genres',
      'styles': 'Styles',
      
      // Stats
      'created': 'Créée',
      'scanned': 'Scannée',
      'lastScanned': 'Dernier scan',
      
      // Actions
      'save': 'Enregistrer',
      'cancel': 'Annuler',
      'delete': 'Supprimer',
      'edit': 'Modifier',
      'confirm': 'Confirmer',
      'close': 'Fermer',
      'loading': 'Chargement...',
      'error': 'Erreur',
      'success': 'Succès',
      'retry': 'Réessayer',
      
      // Profile
      'logout': 'Déconnexion',
      'linkDiscogs': 'Lier avec Discogs',
      'discogsLinked': 'Discogs lié',
      'syncCollection': 'Synchroniser la collection',
      'settings': 'Paramètres',
      'language': 'Langue',
      'theme': 'Thème',
      'darkMode': 'Mode sombre',
      'lightMode': 'Mode clair',
      'about': 'À propos',
      'version': 'Version',
      'privacyPolicy': 'Politique de confidentialité',
      'termsOfService': 'Conditions d\'utilisation',
      
      // Messages
      'welcomeTo': 'Bienvenue sur',
      'errorOccurred': 'Une erreur s\'est produite',
      'tryAgain': 'Réessayez',
      'noResults': 'Aucun résultat',
      'searchNoResults': 'Aucun résultat trouvé pour votre recherche',
      
      // Scanner
      'scanner': 'Scanner',
      'scannerTitle': 'Cadrez les dos de vos vinyles ici !',
      'scannerHint': 'Assurez-vous que la lumière est bonne et que les dos sont visibles.',
      'readyForGemini': 'Prêt pour Gemini...!',
      'takePhotoButton': 'Prendre une photo !',
      'analyzing': 'Analyse en cours...',
      'scannerTipLight': 'Je ne vois pas bien les dos ! Pouvez-vous allumer la lumière ?',
      'scannerTipCloser': 'Rapprochez-vous un peu pour mieux voir les titres !',
      'scannerTipSteady': 'Gardez votre téléphone stable pour une photo plus nette.',
      'scannerSuccess': 'Parfait ! Photo capturée avec succès.',
      'cameraPermissionDenied': 'Permission caméra nécessaire pour scanner',
      'cameraNotAvailable': 'Caméra non disponible',
      'processingImage': 'Traitement de l\'image...',
      'sendingToGemini': 'Envoi à Gemini...',
      'scanZone': 'Scanner la zone',
    },
    
    // ==================== ITALIANO ====================
    'it': {
      // App
      'appTitle': 'VinylScout',
      'appSubtitle': 'La tua collezione di vinili, organizzata',
      'continueWithGoogle': 'Continua con Google',
      'discoverYourCollection': 'Scopri, organizza e goditi la tua collezione',
      
      // Navigation
      'collection': 'Collezione',
      'shelves': 'Scaffali',
      'scan': 'Scansiona',
      'playlists': 'Playlist',
      'profile': 'Profilo',
      
      // Shelves
      'myShelves': 'I miei Scaffali',
      'addShelf': 'Aggiungi scaffale',
      'shelfName': 'Nome dello scaffale',
      'takePhoto': 'Scatta foto',
      'selectPhoto': 'Seleziona foto',
      'noShelvesYet': 'Nessuno scaffale ancora',
      'createFirstShelf': 'Crea il tuo primo scaffale per iniziare',
      'deleteShelf': 'Elimina scaffale',
      'confirmDeleteShelf': 'Sei sicuro di voler eliminare',
      'editName': 'Modifica nome',
      'showHideZones': 'Mostra/nascondi zone',
      'viewFullImage': 'Visualizza immagine completa',
      'resetZoom': 'Reimposta zoom',
      
      // Zones
      'zones': 'Zone',
      'zone': 'Zona',
      'addZone': 'Aggiungi zona',
      'deleteZone': 'Elimina zona',
      'confirmDeleteZone': 'Sei sicuro di voler eliminare la Zona',
      'noZonesDefined': 'Nessuna zona definita',
      'divideShelfIntoZones': 'Dividi il tuo scaffale in zone per organizzare meglio i tuoi vinili',
      'createFirstZone': 'Crea prima zona',
      'useButtonBelow': 'Usa il pulsante qui sotto per iniziare',
      'readyToDiscover': 'Pronto a scoprire i tuoi tesori?',
      'zoneHasAlbums': 'Questa zona ha',
      'albumsAssociated': 'album associati',
      'albumAssociated': 'album associato',
      'albumsWillNotBeDeleted': 'Gli album non verranno eliminati, ma perderanno la loro posizione.',
      'deleteAnyway': 'Elimina comunque',
      'zoneDeleted': 'Zona eliminata',
      'attention': 'Attenzione!',
      
      // Albums
      'albums': 'Album',
      'album': 'Album',
      'myCollection': 'La mia Collezione',
      'searchAlbums': 'Cerca album...',
      'addAlbum': 'Aggiungi album',
      'noAlbums': 'Nessun album',
      'artist': 'Artista',
      'title': 'Titolo',
      'year': 'Anno',
      'genres': 'Generi',
      'styles': 'Stili',
      
      // Stats
      'created': 'Creato',
      'scanned': 'Scansionato',
      'lastScanned': 'Ultima scansione',
      
      // Actions
      'save': 'Salva',
      'cancel': 'Annulla',
      'delete': 'Elimina',
      'edit': 'Modifica',
      'confirm': 'Conferma',
      'close': 'Chiudi',
      'loading': 'Caricamento...',
      'error': 'Errore',
      'success': 'Successo',
      'retry': 'Riprova',
      
      // Profile
      'logout': 'Esci',
      'linkDiscogs': 'Collega con Discogs',
      'discogsLinked': 'Discogs collegato',
      'syncCollection': 'Sincronizza collezione',
      'settings': 'Impostazioni',
      'language': 'Lingua',
      'theme': 'Tema',
      'darkMode': 'Modalità scura',
      'lightMode': 'Modalità chiara',
      'about': 'Informazioni',
      'version': 'Versione',
      'privacyPolicy': 'Informativa sulla privacy',
      'termsOfService': 'Termini di servizio',
      
      // Messages
      'welcomeTo': 'Benvenuto su',
      'errorOccurred': 'Si è verificato un errore',
      'tryAgain': 'Riprova',
      'noResults': 'Nessun risultato',
      'searchNoResults': 'Nessun risultato trovato per la tua ricerca',
      
      // Scanner
      'scanner': 'Scanner',
      'scannerTitle': 'Inquadra i dorsi dei tuoi vinili qui!',
      'scannerHint': 'Assicurati che la luce sia buona e che i dorsi siano visibili.',
      'readyForGemini': 'Pronto per Gemini...!',
      'takePhotoButton': 'Scatta foto!',
      'analyzing': 'Analizzando...',
      'scannerTipLight': 'Non vedo bene i dorsi! Puoi accendere la luce?',
      'scannerTipCloser': 'Avvicinati un po\' per vedere meglio i titoli!',
      'scannerTipSteady': 'Tieni fermo il telefono per una foto più nitida.',
      'scannerSuccess': 'Perfetto! Foto catturata con successo.',
      'cameraPermissionDenied': 'È necessario il permesso della fotocamera per scansionare',
      'cameraNotAvailable': 'Fotocamera non disponibile',
      'processingImage': 'Elaborazione immagine...',
      'sendingToGemini': 'Invio a Gemini...',
      'scanZone': 'Scansiona zona',
    },
    
    // ==================== DEUTSCH ====================
    'de': {
      // App
      'appTitle': 'VinylScout',
      'appSubtitle': 'Deine Schallplattensammlung, organisiert',
      'continueWithGoogle': 'Mit Google fortfahren',
      'discoverYourCollection': 'Entdecke, organisiere und genieße deine Sammlung',
      
      // Navigation
      'collection': 'Sammlung',
      'shelves': 'Regale',
      'scan': 'Scannen',
      'playlists': 'Playlists',
      'profile': 'Profil',
      
      // Shelves
      'myShelves': 'Meine Regale',
      'addShelf': 'Regal hinzufügen',
      'shelfName': 'Regalname',
      'takePhoto': 'Foto aufnehmen',
      'selectPhoto': 'Foto auswählen',
      'noShelvesYet': 'Noch keine Regale',
      'createFirstShelf': 'Erstelle dein erstes Regal, um loszulegen',
      'deleteShelf': 'Regal löschen',
      'confirmDeleteShelf': 'Bist du sicher, dass du löschen möchtest',
      'editName': 'Name bearbeiten',
      'showHideZones': 'Zonen anzeigen/ausblenden',
      'viewFullImage': 'Vollbild anzeigen',
      'resetZoom': 'Zoom zurücksetzen',
      
      // Zones
      'zones': 'Zonen',
      'zone': 'Zone',
      'addZone': 'Zone hinzufügen',
      'deleteZone': 'Zone löschen',
      'confirmDeleteZone': 'Bist du sicher, dass du Zone löschen möchtest',
      'noZonesDefined': 'Keine Zonen definiert',
      'divideShelfIntoZones': 'Teile dein Regal in Zonen auf, um deine Schallplatten besser zu organisieren',
      'createFirstZone': 'Erste Zone erstellen',
      'useButtonBelow': 'Verwende den Button unten, um loszulegen',
      'readyToDiscover': 'Bereit, deine Schätze zu entdecken?',
      'zoneHasAlbums': 'Diese Zone hat',
      'albumsAssociated': 'zugeordnete Alben',
      'albumAssociated': 'zugeordnetes Album',
      'albumsWillNotBeDeleted': 'Die Alben werden nicht gelöscht, verlieren aber ihren Standort.',
      'deleteAnyway': 'Trotzdem löschen',
      'zoneDeleted': 'Zone gelöscht',
      'attention': 'Achtung!',
      
      // Albums
      'albums': 'Alben',
      'album': 'Album',
      'myCollection': 'Meine Sammlung',
      'searchAlbums': 'Alben suchen...',
      'addAlbum': 'Album hinzufügen',
      'noAlbums': 'Keine Alben',
      'artist': 'Künstler',
      'title': 'Titel',
      'year': 'Jahr',
      'genres': 'Genres',
      'styles': 'Stile',
      
      // Stats
      'created': 'Erstellt',
      'scanned': 'Gescannt',
      'lastScanned': 'Zuletzt gescannt',
      
      // Actions
      'save': 'Speichern',
      'cancel': 'Abbrechen',
      'delete': 'Löschen',
      'edit': 'Bearbeiten',
      'confirm': 'Bestätigen',
      'close': 'Schließen',
      'loading': 'Lädt...',
      'error': 'Fehler',
      'success': 'Erfolg',
      'retry': 'Erneut versuchen',
      
      // Profile
      'logout': 'Abmelden',
      'linkDiscogs': 'Mit Discogs verknüpfen',
      'discogsLinked': 'Discogs verknüpft',
      'syncCollection': 'Sammlung synchronisieren',
      'settings': 'Einstellungen',
      'language': 'Sprache',
      'theme': 'Design',
      'darkMode': 'Dunkelmodus',
      'lightMode': 'Hellmodus',
      'about': 'Über',
      'version': 'Version',
      'privacyPolicy': 'Datenschutzrichtlinie',
      'termsOfService': 'Nutzungsbedingungen',
      
      // Messages
      'welcomeTo': 'Willkommen bei',
      'errorOccurred': 'Ein Fehler ist aufgetreten',
      'tryAgain': 'Erneut versuchen',
      'noResults': 'Keine Ergebnisse',
      'searchNoResults': 'Keine Ergebnisse für deine Suche gefunden',
      
      // Scanner
      'scanner': 'Scanner',
      'scannerTitle': 'Rahme die Rücken deiner Schallplatten hier ein!',
      'scannerHint': 'Achte auf gute Beleuchtung und dass die Rücken sichtbar sind.',
      'readyForGemini': 'Bereit für Gemini...!',
      'takePhotoButton': 'Foto aufnehmen!',
      'analyzing': 'Analysiere...',
      'scannerTipLight': 'Ich kann die Rücken nicht gut sehen! Kannst du das Licht einschalten?',
      'scannerTipCloser': 'Komm etwas näher, um die Titel besser zu sehen!',
      'scannerTipSteady': 'Halte dein Handy ruhig für ein schärferes Foto.',
      'scannerSuccess': 'Perfekt! Foto erfolgreich aufgenommen.',
      'cameraPermissionDenied': 'Kameraberechtigung zum Scannen erforderlich',
      'cameraNotAvailable': 'Kamera nicht verfügbar',
      'processingImage': 'Bild wird verarbeitet...',
      'sendingToGemini': 'Sende an Gemini...',
      'scanZone': 'Zone scannen',
    },
  };

  String _getLanguageCode() {
    return _localizedValues.containsKey(locale.languageCode) 
        ? locale.languageCode 
        : 'en';
  }

  String _get(String key) {
    return _localizedValues[_getLanguageCode()]?[key] ?? 
           _localizedValues['en']![key] ?? 
           key;
  }

  // ==================== GETTERS ====================
  
  // App
  String get appTitle => _get('appTitle');
  String get appSubtitle => _get('appSubtitle');
  String get continueWithGoogle => _get('continueWithGoogle');
  String get discoverYourCollection => _get('discoverYourCollection');
  
  // Navigation
  String get collection => _get('collection');
  String get shelves => _get('shelves');
  String get scan => _get('scan');
  String get playlists => _get('playlists');
  String get profile => _get('profile');
  
  // Shelves
  String get myShelves => _get('myShelves');
  String get addShelf => _get('addShelf');
  String get shelfName => _get('shelfName');
  String get takePhoto => _get('takePhoto');
  String get selectPhoto => _get('selectPhoto');
  String get noShelvesYet => _get('noShelvesYet');
  String get createFirstShelf => _get('createFirstShelf');
  String get deleteShelf => _get('deleteShelf');
  String get confirmDeleteShelf => _get('confirmDeleteShelf');
  String get editName => _get('editName');
  String get showHideZones => _get('showHideZones');
  String get viewFullImage => _get('viewFullImage');
  String get resetZoom => _get('resetZoom');
  
  // Zones
  String get zones => _get('zones');
  String get zone => _get('zone');
  String get addZone => _get('addZone');
  String get deleteZone => _get('deleteZone');
  String get confirmDeleteZone => _get('confirmDeleteZone');
  String get noZonesDefined => _get('noZonesDefined');
  String get divideShelfIntoZones => _get('divideShelfIntoZones');
  String get createFirstZone => _get('createFirstZone');
  String get useButtonBelow => _get('useButtonBelow');
  String get readyToDiscover => _get('readyToDiscover');
  String get zoneHasAlbums => _get('zoneHasAlbums');
  String get albumsAssociated => _get('albumsAssociated');
  String get albumAssociated => _get('albumAssociated');
  String get albumsWillNotBeDeleted => _get('albumsWillNotBeDeleted');
  String get deleteAnyway => _get('deleteAnyway');
  String get zoneDeleted => _get('zoneDeleted');
  String get attention => _get('attention');
  
  // Albums
  String get albums => _get('albums');
  String get album => _get('album');
  String get myCollection => _get('myCollection');
  String get searchAlbums => _get('searchAlbums');
  String get addAlbum => _get('addAlbum');
  String get noAlbums => _get('noAlbums');
  String get artist => _get('artist');
  String get title => _get('title');
  String get year => _get('year');
  String get genres => _get('genres');
  String get styles => _get('styles');
  
  // Stats
  String get created => _get('created');
  String get scanned => _get('scanned');
  String get lastScanned => _get('lastScanned');
  
  // Actions
  String get save => _get('save');
  String get cancel => _get('cancel');
  String get delete => _get('delete');
  String get edit => _get('edit');
  String get confirm => _get('confirm');
  String get close => _get('close');
  String get loading => _get('loading');
  String get error => _get('error');
  String get success => _get('success');
  String get retry => _get('retry');
  
  // Profile
  String get logout => _get('logout');
  String get linkDiscogs => _get('linkDiscogs');
  String get discogsLinked => _get('discogsLinked');
  String get syncCollection => _get('syncCollection');
  String get settings => _get('settings');
  String get language => _get('language');
  String get theme => _get('theme');
  String get darkMode => _get('darkMode');
  String get lightMode => _get('lightMode');
  String get about => _get('about');
  String get version => _get('version');
  String get privacyPolicy => _get('privacyPolicy');
  String get termsOfService => _get('termsOfService');
  
  // Messages
  String get welcomeTo => _get('welcomeTo');
  String get errorOccurred => _get('errorOccurred');
  String get tryAgain => _get('tryAgain');
  String get noResults => _get('noResults');
  String get searchNoResults => _get('searchNoResults');
  
  // Scanner
  String get scanner => _get('scanner');
  String get scannerTitle => _get('scannerTitle');
  String get scannerHint => _get('scannerHint');
  String get readyForGemini => _get('readyForGemini');
  String get takePhotoButton => _get('takePhotoButton');
  String get analyzing => _get('analyzing');
  String get scannerTipLight => _get('scannerTipLight');
  String get scannerTipCloser => _get('scannerTipCloser');
  String get scannerTipSteady => _get('scannerTipSteady');
  String get scannerSuccess => _get('scannerSuccess');
  String get cameraPermissionDenied => _get('cameraPermissionDenied');
  String get cameraNotAvailable => _get('cameraNotAvailable');
  String get processingImage => _get('processingImage');
  String get sendingToGemini => _get('sendingToGemini');
  String get scanZone => _get('scanZone');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['es', 'en', 'fr', 'it', 'de'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
