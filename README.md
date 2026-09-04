# SBU2

Application iOS minimaliste en SwiftUI pour lire et piloter un BMS **JBD**
(aussi vendu sous les noms Xiaoxiang, Overkill Solar, LLT Power…) via son
module Bluetooth LE.

Réécriture depuis zéro de [SBU](https://github.com/atomtoto/SBU) : seule la
connaissance du protocole a été reprise, tout le code est neuf et repose
uniquement sur SwiftUI, `Observation` et CoreBluetooth.

## Fonctionnalités

- Recherche des modules JBD à proximité (service BLE `FF00`) et connexion.
- Rafraîchissement automatique une fois par seconde, avec reconnexion
  automatique si le dongle coupe la liaison.
- Tension du pack, courant, puissance, état de charge, capacité restante et
  estimation du temps de charge / d'autonomie.
- Tension de chaque cellule, écart maximal, cellules en cours d'équilibrage.
- Températures des sondes NTC.
- Protections actives (surtension, sous-tension, surintensité, court-circuit…).
- Activation / coupure des MOSFET de charge et de décharge, avec confirmation.

## Prérequis

- Xcode 16 ou ultérieur.
- iOS 17 minimum.
- Un iPhone ou iPad **réel** : le simulateur n'expose pas de Bluetooth LE.

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

Le workflow `.github/workflows/ci.yml` fait la même chose sur un runner macOS
à chaque poussée sur `main` ou sur une branche `claude/**`. Le dépôt étant
privé, ces minutes sont facturées ×10 : ajoutez `[skip ci]` au message de
commit pour les changements qui ne touchent pas au code.

## Organisation du code

| Fichier | Rôle |
| --- | --- |
| `SBU2/Model/JBDProtocol.swift` | Construction et validation des trames JBD. |
| `SBU2/Model/FrameAssembler.swift` | Recomposition des trames à partir des notifications BLE. |
| `SBU2/Model/BMSReading.swift` | Décodage des registres `0x03` et `0x04`. |
| `SBU2/Bluetooth/BMSConnection.swift` | Scan, connexion, interrogation périodique, écritures. |
| `SBU2/Views/ScanView.swift` | Liste des appareils détectés. |
| `SBU2/Views/MonitorView.swift` | Tableau de bord du pack connecté. |
| `SBU2Tests/` | Tests du protocole et du décodage (Swift Testing). |

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

- Les BMS protégés par un mot de passe refusent les écritures : la saisie du
  mot de passe n'est pas implémentée.
- La lecture et l'écriture de la configuration complète (seuils de protection,
  capacités, paramètres d'équilibrage) ne sont pas reprises.
