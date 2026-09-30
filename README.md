# SBU2

Applications iOS, macOS (Mac Catalyst) et watchOS en SwiftUI pour lire et piloter un BMS **JBD** (aka Xiaoxiang) ou **JK** via son module Bluetooth LE.

Tout le code est neuf et repose
uniquement sur SwiftUI, `Observation` et CoreBluetooth.

## Fonctionnalités

- Recherche des modules JBD/JK à proximité et connexion.
- Rafraîchissement automatique une fois par seconde, avec reconnexion
  automatique si le dongle coupe la liaison.
- Tension du pack, courant, puissance, état de charge, capacité restante et
  estimation du temps de charge / d'autonomie.
- Tension de chaque cellule, écart maximal, cellules en cours d'équilibrage.
- Températures des sondes NTC.
- Protections actives (surtension, sous-tension, surintensité, court-circuit…).
- Activation / coupure des MOSFET de charge et de décharge, avec confirmation.
- Synchronisation iCloud des préférences de l'app et des profils de BMS entre
  iPhone, iPad, Mac et Apple Watch, avec association explicite du même BMS.
- Sur Apple Watch : connexion Bluetooth directe au BMS, lecture de l'état de
  charge, tension, courant, puissance, cellules, températures et alertes, puis
  commandes MOSFET avec confirmation. Aucun iPhone n'est requis à proximité.
  Les mesures de plus de cinq secondes sont signalées comme périmées et les
  commandes MOSFET sont alors désactivées jusqu'à la prochaine mesure valide.

## Prérequis

- Xcode avec les SDK iOS, macOS et watchOS 26 ou ultérieurs.
- iOS 26 minimum.
- macOS 26 minimum pour la version Mac Catalyst.
- watchOS 26 minimum pour l'app Apple Watch.
- Un iPhone, iPad, Mac ou une Apple Watch **réels** pour le Bluetooth LE : le
  simulateur permet d'essayer l'appareil de démonstration, sans BMS réel.

## Compilation

```sh
open SBU2.xcodeproj
```

L'identifiant de bundle est `atom.sbu2` et l'équipe de signature est
préremplie ; adaptez-les dans les réglages de la cible si nécessaire.

Pour lancer les tests unitaires :

```sh
xcodebuild test -scheme SBU2 -destination 'platform=iOS Simulator,name=iPhone 16'
```

Pour compiler l'app Apple Watch :

```sh
xcodebuild build -scheme SBU2Watch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```

La même cible `SBU2` produit aussi l'app Mac Catalyst, avec une interface qui
s'adapte à la largeur de la fenêtre :

```sh
xcodebuild build -scheme SBU2 -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO
```

Sur Mac, les menus contextuels s'ouvrent au clic droit et la remise à zéro du
trajet GPS se trouve dans la barre d'outils. Les activités de charge et l'app
Apple Watch restent propres à la version iOS.

La cible `SBU2Watch` est intégrée à l'app iOS. Sur la montre, ouvrez SBU2,
choisissez un BMS détecté, puis parcourez ses mesures. Les réglages enregistrés
sur l'iPhone et ceux de la montre peuvent partager un profil iCloud. La liaison directe est
maintenue pendant la consultation de l'app ; watchOS peut suspendre l'app quand
elle passe en arrière-plan. Il n'y a pas de complication sur le cadran.

Le workflow `.github/workflows/ci.yml` fait la même chose sur un runner macOS
à chaque poussée sur `main` ou sur une branche `claude/**` — un run par commit,
que la branche ait une pull request ouverte ou non. Le dépôt étant privé, ces
minutes sont facturées ×10 : ajoutez `[skip ci]` au message de commit pour les
changements qui ne touchent pas au code.

## Synchronisation iCloud

La synchronisation est activée par défaut et utilise le stockage clé-valeur
iCloud (`NSUbiquitousKeyValueStore`). Les appareils doivent être connectés au
même compte iCloud. Le thème, l'unité de capacité, le contraste des cellules et
l'affichage du BMS de démonstration sont partagés automatiquement. Pour un BMS
réel, seuls les appareils associés explicitement à son profil partagent son nom,
son icône, ses styles, ses paramètres d'affichage, de chimie, de limite de charge
et de recharge programmée.

Les mots de passe du BMS, l'auto-connexion, le maintien de l'écran allumé et la
confirmation des commandes MOSFET restent locaux. Les mesures Bluetooth, les
commandes matérielles et le trajet GPS ne sont pas synchronisés. Synchroniser un
réglage de limite ou de recharge programmée ne déclenche aucune commande sur le
BMS : ces fonctions restent déclaratives comme indiqué dans les limites connues.

### Configurer la signature

Les entitlements de `SBU2` sur iOS, de sa variante Mac Catalyst et de
`SBU2Watch` déclarent le même `com.apple.developer.ubiquity-kvstore-identifier` :
`$(TeamIdentifierPrefix)atom.sbu2`. Gardez un identifiant de stockage commun,
y compris si vous adaptez les identifiants de bundle, et utilisez la même équipe
de développement pour toutes ces cibles, suivant la
[configuration de stockage clé-valeur commun décrite par Apple](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/iCloudFundametals.html).

Dans le compte Apple Developer, activez iCloud avec le service **Key-value
storage** pour les App IDs de l'app et de la montre. Dans **Signing &
Capabilities** d'Xcode, vérifiez la capacité iCloud et le service **Key-value
storage** de chaque cible, puis laissez la signature automatique actualiser les
profils de provisioning ; avec une signature manuelle, régénérez les profils
correspondants. Aucun conteneur CloudKit ni schéma CloudKit n'est nécessaire.
Une compilation avec `CODE_SIGNING_ALLOWED=NO` vérifie le code, mais ne valide pas
les droits iCloud ni les échanges entre appareils.

### Associer un BMS sur plusieurs appareils

1. Vérifiez que **Settings → iCloud → Sync with iCloud** est activé sur les
   appareils concernés. Sur la montre, le bouton iCloud de la liste des batteries
   ouvre ce réglage.
2. Sur le premier appareil, connectez le BMS, ouvrez ses **Settings**, puis
   choisissez **Share This BMS with iCloud**. Cela crée son profil partagé.
3. Sur un autre appareil, connectez ce même BMS et choisissez **Link an Existing
   Profile** dans ses réglages. Sélectionnez le profil créé à l'étape précédente.
   Seuls les profils compatibles avec le protocole détecté sont proposés.
4. Confirmez : le nom, l'icône et les réglages partagés du profil remplacent ceux
   enregistrés sur cet appareil. Son mot de passe et son choix d'auto-connexion
   sont conservés.

Sur la montre, touchez le bouton nuage à côté d'une batterie dans la liste pour
ouvrir **iCloud Profile**, puis créer un profil ou en sélectionner un existant. Les identifiants
Bluetooth ne sont pas les mêmes sur tous les appareils : l'app ne devine pas
quels BMS correspondent. La sélection du profil reste explicite.

**Stop Sharing on This Device** — ou **Stop Sharing on This Watch** — conserve
les réglages présents sur cet appareil et laisse le profil disponible ailleurs.
**Forget This BMS** supprime aussi son profil partagé et réinitialise les choix
partagés sur les appareils qui y étaient associés ; leurs mots de passe et
choix d'auto-connexion locaux sont conservés. La confirmation indique cette
suppression entre appareils.

### Hors ligne, conflits et limites

Les réglages sont toujours enregistrés localement. Les modifications sont mises
en attente hors ligne et sont transférées lorsqu'iCloud est disponible. L'app
actualise les échanges à son ouverture et lorsqu'elle revient au premier plan ;
**Sync Now** demande également une actualisation, sans garantir un transfert
réseau immédiat. Les notifications iCloud appliquent les changements reçus à un
BMS déjà ouvert.

Pour un profil de BMS modifié sur plusieurs appareils, l'édition dont
l'horodatage est le plus récent l'emporte sur l'ensemble des réglages partagés
du profil. Les champs d'un profil ne sont pas fusionnés individuellement ; les
préférences de l'app sont, elles, arbitrées séparément. En cas d'horodatage égal,
l'identifiant de modification départage les éditions de manière déterministe.
La suppression d'un profil reste définitive, même face à une modification hors
ligne arrivée plus tard.

Le stockage clé-valeur iCloud est
[limité à 1 Mo et 1 024 clés par app et compte](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForKey-ValueDataIniCloud.html).
Une image Genmoji volumineuse peut dépasser le budget avec les autres profils :
le profil concerné reste enregistré localement et le statut iCloud signale que
certains réglages ou icônes n'ont pas pu être transférés. Choisissez un symbole
ou un emoji plus léger pour réduire sa taille.

Lors d'un changement de compte Apple, la synchronisation est automatiquement
désactivée et les associations, la copie des profils iCloud et les modifications
en attente de l'ancien compte sont effacées. Les réglages locaux restent
disponibles. Réactivez explicitement la synchronisation et associez les BMS aux
profils du compte courant : les profils et la file d'attente de l'ancien compte
ne sont pas envoyés automatiquement vers le nouveau.

## Organisation du code

| Fichier | Rôle |
| --- | --- |
| `SBU2/Model/Protocols/BMSProtocolAdapter.swift` | Interface commune à toutes les familles de BMS, et registre des familles connues. |
| `SBU2/Model/Protocols/JBDAdapter.swift` | Implémentation JBD : commandes de scrutation, séquences d'écriture, lecture des réponses. |
| `SBU2/Model/JBDProtocol.swift` | Construction et validation des trames JBD. |
| `SBU2/Model/FrameAssembler.swift` | Recomposition des trames à partir des notifications BLE. |
| `SBU2/Model/BMSReading.swift` | Décodage des registres `0x03` et `0x04`. |
| `SBU2/Bluetooth/BMSConnection.swift` | Scan, connexion, file d'envoi, interrogation périodique. |
| `SBU2/Views/DeviceListView.swift` | Liste des appareils détectés. |
| `SBU2/Views/Overview/` | Tableau de bord du pack, repris à l'identique de SBU. |
| `SBU2/Views/GPS/` | Cadrans et relevés de trajet, repris à l'identique de SBU. |
| `SBU2/Views/Settings/` | Réglages appareil et application. |
| `SBU2/Model/ICloudSettingsSync.swift` | Synchronisation clé-valeur iCloud, profils explicitement associés, conflits et file d'attente hors ligne. |
| `SBU2Tests/` | Tests du protocole et du décodage (Swift Testing). |
| `SBU2Watch/` | Interface Apple Watch, utilisant directement le moteur Bluetooth et les modèles communs. |

## Plusieurs familles de BMS

`BMSConnection` ne nomme jamais un registre ni une trame : il demande ses
commandes à un `BMSProtocolAdapter` et lui redonne les octets reçus, qui lui
reviennent sous forme d'événements (`basicInfo`, `cellVoltages`, écriture
acceptée ou refusée). Chaque famille se décrit dans un `BMSProtocolDescriptor` :
son profil GATT, la façon de reconnaître un appareil à partir de sa publicité
BLE, et une fabrique. Ajouter une famille revient donc à écrire un adaptateur et
à l'ajouter à `BMSProtocolRegistry.descriptors` — le scan couvre alors
automatiquement son service, et aucune vue ne change. La famille retenue est
mémorisée par appareil (`DeviceSettings.protocolID`).

Seul JBD et JK sont implémentés aujourd'hui.

## Une commande à la fois

Le dongle est un pont série : une requête écrite pendant qu'il répond encore
tronque la réponse en cours, et CoreBluetooth jette silencieusement une écriture
« sans réponse » émise alors que sa propre file est pleine. Les commandes
passent donc par une file vidée d'un cran toutes les 150 ms, et chacune attend
la réponse de la précédente (avec expiration, et jamais pendant que des octets
arrivent encore). Un tampon resté incomplet est abandonné au bout d'1,5 s, un
silence de 5 s remet le flux à zéro, un silence de 12 s relance la liaison.

## Protocole JBD en deux mots

Toutes les trames ont la même forme :

```
0xDD  <registre>  <statut>  <longueur>  <données…>  <checksum hi>  <checksum lo>  0x77
```

En émission, le second octet indique le sens (`0xA5` lecture, `0x5A` écriture)
et le troisième le registre. En réception, le second octet répète le registre et
le troisième vaut `0x00` en cas de succès. Le checksum vaut
`0x10000 - somme(statut + longueur + données)`, tronqué sur 16 bits.

Registres utilisés :

| Registre | Contenu |
| --- | --- |
| `0x03` | Informations générales : tension, courant, capacité, SoC, protections, MOSFET, températures. |
| `0x04` | Tension de chaque cellule, en millivolts. |
| `0x00` / `0x01` | Ouverture / fermeture du mode usine (obligatoire avant toute écriture). |
| `0xE1` | Commande des MOSFET : bit 0 coupe la charge, bit 1 la décharge. |

## Limites connues

- La lecture et l'écriture de la configuration complète (seuils de protection,
  capacités, paramètres d'équilibrage) ne sont pas reprises.
- L'enregistrement des mesures et les graphiques ne sont
  pas repris.
- La limite de charge est réglable mais n'agit sur rien : aucun code ne lit `chargeLimitSOC` en dehors de l'interface.
- L'interface est en anglais. Une localisation
  française et autres viendra plus tard.
