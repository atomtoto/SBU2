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
sur l'iPhone et ceux de la montre sont indépendants. La liaison directe est
maintenue pendant la consultation de l'app ; watchOS peut suspendre l'app quand
elle passe en arrière-plan. Il n'y a pas de complication sur le cadran.

Le workflow `.github/workflows/ci.yml` fait la même chose sur un runner macOS
à chaque poussée sur `main` ou sur une branche `claude/**` — un run par commit,
que la branche ait une pull request ouverte ou non. Le dépôt étant privé, ces
minutes sont facturées ×10 : ajoutez `[skip ci]` au message de commit pour les
changements qui ne touchent pas au code.

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
