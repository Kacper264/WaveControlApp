# Logigrammes WaveControl (Mermaid)

Ce document regroupe tous les logigrammes du projet en syntaxe Mermaid `flowchart`, pour une utilisation directe dans les outils compatibles Mermaid.

Pour améliorer la lisibilité visuelle, chaque logigramme utilise :
- un espacement augmenté entre les nœuds,
- une palette cohérente (début/fin, action, décision, résultat),
- une structuration des branches qui évite les libellés collés.

---

## 0) Navigation haut niveau de l'application

```mermaid
---
config:
  theme: base
  flowchart:
    nodeSpacing: 44
    rankSpacing: 60
    curve: linear
  themeVariables:
    fontSize: 13px
    lineColor: '#334155'
    primaryTextColor: '#0f172a'
    fontFamily: Inter,Segoe UI,Arial
  layout: fixed
---
flowchart TB
    C["HomeScreen"] --> E["SettingsScreen"] & G["ViewConfigsScreen"] & F["Monitoring appareils"] & I["MqttControlPage"] & H["ConfigurationScreen"]
    H --> K["Config Mouvements / Gestion télécommandes IR"] & C
    K --> L["IRDeviceDetailScreen"]
    E --> C
    F --> C
    G --> C
    I --> C
    A(["Lancement app"]) --> C

     C:::action
     E:::action
     G:::action
     F:::action
     I:::action
     H:::action
     K:::action
     L:::action
     A:::start
    classDef start fill:#0ea5e9,stroke:#0369a1,color:#ffffff,stroke-width:2px
    classDef action fill:#e2e8f0,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    classDef decision fill:#fef3c7,stroke:#d97706,color:#78350f,stroke-width:2px
```

---


## 1) Navigation globale et lancement

```mermaid
graph TD
    %% Nœud de départ
    Start([Lancement Application WaveControl]) --> Home[Home - Hub principale]

    %% Navigation supérieure
    Home --> ModeSel[Mode sélectionné]
    Home --> Params[Paramètres]

    %% Logique de sélection
    Params --> Choice{Sélection Mode}

    %% Branches des modes
    Choice --> User[Mode utilisateur]
    Choice --> Tech[Mode Technicien]
    Choice --> Dev[Mode Developpeur]

    %% Actions Mode Utilisateur
    User --> ViewConfig[Voir configuration]
    User --> Monitor[Monitoring]

    %% Actions Mode Technicien
    Tech --> Monitor
    Tech --> Config[Configuration]

    %% Actions Mode Développeur
    Dev --> Config
    Dev --> Test[TEST MQTT]
    Dev --> Monitor

    %% Style (Optionnel pour correspondre à l'image)
    style Choice fill:#fff,stroke:#333,stroke-width:2px
    style Start fill:#fff,stroke:#333,stroke-width:1px
    style Home fill:#fff,stroke:#333,stroke-width:1px
```

---

## 2) Commande MQTT complète

```mermaid
---
config:
  theme: base
  flowchart:
    nodeSpacing: 40
    rankSpacing: 50
    curve: linear
  themeVariables:
    fontSize: 13px
    lineColor: '#334155'
    primaryTextColor: '#0f172a'
    fontFamily: Inter,Segoe UI,Arial
  layout: dagre
---
flowchart TB
    A["Action utilisateur"] --> B["UI déclenche commande"]
    B --> C["Service MQTT envoyé"]
    C --> D["Broker MQTT"]
    D --> E["Équipement exécute"] & G["Application reçoit retour"]
    E --> F["Équipement publie nouvel état"]
    F --> D
    G --> H["Mise à jour état local"]
    H --> I["UI rafraîchie"]

     A:::start
     B:::action
     C:::action
     D:::action
     E:::action
     G:::action
     F:::action
     H:::action
     I:::result
    classDef start fill:#0ea5e9,stroke:#0369a1,color:#ffffff,stroke-width:2px
    classDef action fill:#e2e8f0,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    classDef result fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:2px
```

---

## 3) Reconnexion réseau

```mermaid
%%{init: {'theme':'base','flowchart':{'nodeSpacing':42,'rankSpacing':58,'curve':'linear'},'themeVariables':{'fontSize':'13px','lineColor':'#334155','primaryTextColor':'#0f172a','fontFamily':'Inter,Segoe UI,Arial'}}}%%
flowchart TD
    A[Application connectée] --> B{Réseau disponible ?}
    B -->|Oui| C[Fonctionnement nominal]
    B -->|Non| D[Perte réseau détectée]
    D --> E[Statut MQTT déconnecté]
    E --> F[Surveillance connectivité]
    F --> G{Réseau revenu ?}
    G -->|Non| F
    G -->|Oui| H[Tentative reconnexion MQTT]
    H --> I{Succès ?}
    I -->|Oui| J[Réabonnement topics]
    J --> K[Resynchronisation états]
    K --> C
    I -->|Non| L[Retry temporisé]
    L --> H

    classDef start fill:#0ea5e9,stroke:#0369a1,color:#ffffff,stroke-width:2px;
    classDef action fill:#e2e8f0,stroke:#64748b,color:#0f172a,stroke-width:1.5px;
    classDef decision fill:#fef3c7,stroke:#d97706,color:#78350f,stroke-width:2px;
    classDef result fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:2px;
    classDef warning fill:#fee2e2,stroke:#dc2626,color:#7f1d1d,stroke-width:1.8px;

    class A start;
    class D,E,F,H,J,K,L action;
    class B,G,I decision;
    class C result;
```

---



## 5) Workflow configuration bracelet

```mermaid
---
config:
  theme: base
  flowchart:
    nodeSpacing: 42
    rankSpacing: 58
    curve: linear
  themeVariables:
    fontSize: 13px
    lineColor: '#334155'
    primaryTextColor: '#0f172a'
    fontFamily: Inter,Segoe UI,Arial
  layout: fixed
---
flowchart TB
    A["Entrée écran Configuration"] --> B["Demande possibilités bracelet"]
    B --> C["Réception possibilités"]
    C --> D["Chargement config existante"]
    D --> E{"Configuration existante ?"}
    E -- Oui --> F["Afficher"]
    E -- Non --> G["Assistant de création"]
    G --> H["Ajout association mouvement"]
    H --> I["Validation utilisateur"]
    I --> J["Envoi via MQTT"]
    J --> K{"Statut succès ?"}
    K -- Oui --> L["Confirmation + rechargement"]
    K -- Non --> M["Erreur"]
    F --> n1["Choix Bouton"]
    n1 -- Ajout Config --> H
    n1 -- Infrarouge --> n2["Gestion Infra-Rouge"]

    n1@{ shape: diam}
    n2@{ shape: rect}
     A:::start
     B:::action
     C:::action
     D:::action
     E:::decision
     F:::action
     G:::action
     H:::action
     I:::action
     J:::action
     K:::decision
     L:::result
     M:::warning
     n1:::decision
     n2:::action
    classDef start fill:#0ea5e9,stroke:#0369a1,color:#ffffff,stroke-width:2px
    classDef action fill:#e2e8f0,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    classDef decision fill:#fef3c7,stroke:#d97706,color:#78350f,stroke-width:2px
    classDef result fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:2px
    classDef warning fill:#fee2e2,stroke:#dc2626,color:#7f1d1d,stroke-width:1.8px
```

---



## 6) Gestion des périphériques IR

```mermaid
---
config:
  theme: base
  flowchart:
    nodeSpacing: 42
    rankSpacing: 58
    curve: linear
  themeVariables:
    fontSize: 13px
    lineColor: '#334155'
    primaryTextColor: '#0f172a'
    fontFamily: Inter,Segoe UI,Arial
  layout: fixed
---
flowchart TB
    A["Ouverture module IR"] --> B["Demande liste télécommandes"]
    B --> C["Affichage liste"]
    C --> D{"Action utilisateur"}
    D -- Ajouter --> E["Création télécommande"]
    D -- Supprimer --> G["Confirmation suppression"]
    F["Détail périphérique"] --> H["Rafraîchissement liste"]
    H --> I["État IR synchronisé"]
    G --> H
    E --> H
    D -- Consulter --> F

     A:::start
     B:::action
     C:::action
     D:::decision
     E:::action
     G:::action
     F:::action
     H:::action
     I:::result
    classDef start fill:#0ea5e9,stroke:#0369a1,color:#ffffff,stroke-width:2px
    classDef action fill:#e2e8f0,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    classDef decision fill:#fef3c7,stroke:#d97706,color:#78350f,stroke-width:2px
    classDef result fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:2px
```

---

## 7) Traitement d'un message entrant

```mermaid
---
config:
  theme: base
  flowchart:
    nodeSpacing: 42
    rankSpacing: 58
    curve: linear
  themeVariables:
    fontSize: 13px
    lineColor: '#334155'
    primaryTextColor: '#0f172a'
    fontFamily: Inter,Segoe UI,Arial
  layout: fixed
---
flowchart TB
    A["Message MQTT entrant"] --> B["Identifier topic"]
    B --> C["Parser payload"]
    C --> D{"Payload valide ?"}
    D -- Oui --> E["Mettre à jour état local"]
    D -- Non --> F["Journaliser erreur"]
    E --> G["Notifier écrans"]
    F --> G
    G --> H["Interface actualisée"]

     A:::start
     B:::action
     C:::action
     D:::decision
     E:::action
     F:::warning
     G:::action
     H:::result
    classDef start fill:#0ea5e9,stroke:#0369a1,color:#ffffff,stroke-width:2px
    classDef action fill:#e2e8f0,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    classDef decision fill:#fef3c7,stroke:#d97706,color:#78350f,stroke-width:2px
    classDef result fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:2px
    classDef warning fill:#fee2e2,stroke:#dc2626,color:#7f1d1d,stroke-width:1.8px
```

---

## 8) Workflow ajout d'action dans une télécommande IR

```mermaid
---

---
config:
  theme: base
  flowchart:
    nodeSpacing: 42
    rankSpacing: 58
    curve: linear
  themeVariables:
    fontSize: 13px
    lineColor: '#334155'
    primaryTextColor: '#0f172a'
    fontFamily: Inter,Segoe UI,Arial
  layout: fixed
---
flowchart TB
    A["Ouvrir détail de la télécommande"] --> B["Cliquer Ajouter action"]
    B --> C["Saisir nom de l'action"]
    C --> D{"Nom valide ?"}
    D -- Non --> E["Afficher erreur de saisie"]
    E --> C
    D -- Oui --> F["Passer en mode apprentissage IR"]
    F --> G["Demander appui sur bouton physique"]
    G --> H{"Signal IR reçu ?"}
    H -- Non --> I["Timeout / nouvelle tentative"]
    I --> G
    H -- Oui --> J["Enregistrer code IR"]
    J --> K["Publier mise à jour MQTT"]
    K --> L{"Retour de confirmation ?"}
    L -- Non --> M["Alerte échec + conserver brouillon"]
    L -- Oui --> N["Rafraîchir liste des actions"]
    N --> O["Action visible dans la télécommande"]

     A:::start
     B:::action
     C:::action
     D:::decision
     E:::warning
     F:::action
     G:::action
     H:::decision
     I:::warning
     J:::action
     K:::action
     L:::decision
     M:::warning
     N:::action
     O:::result
    classDef start fill:#0ea5e9,stroke:#0369a1,color:#ffffff,stroke-width:2px
    classDef action fill:#e2e8f0,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    classDef decision fill:#fef3c7,stroke:#d97706,color:#78350f,stroke-width:2px
    classDef result fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:2px
    classDef warning fill:#fee2e2,stroke:#dc2626,color:#7f1d1d,stroke-width:1.8px
```

---
## 9) Workflow menu Paramètres

```mermaid
---
config:
  theme: base
  flowchart:
    nodeSpacing: 42
    rankSpacing: 58
    curve: linear
  themeVariables:
    fontSize: 13px
    lineColor: '#334155'
    primaryTextColor: '#0f172a'
    fontFamily: Inter,Segoe UI,Arial
  layout: fixed
---
flowchart TB
    A["Ouvrir Settings depuis Home"] --> B["Afficher menu Paramètres"]
    B --> C{"Choix utilisateur"}
    C -- Langue --> D["Changer langue"]
    C -- Thème --> E["Basculer clair/sombre"]
    C -- MQTT --> F["Modifier serveur/port/login/mdp"]
    C -- Mode --> G["Demander changement de mode"]
    C -- Notifications --> H@{ label: "Activer/désactiver types d'alertes" }
    D --> J["Enregistrer préférence locale"]
    E --> J
    H --> J
    F --> K{"Mot de passe MQTT saisi ?"}
    K -- Non --> L["Erreur : mot de passe requis"]
    L --> F
    K -- Oui --> M["Sauvegarder config MQTT"]
    M --> N["Informer : redémarrage conseillé"]
    G --> O{"Mode avancé ?"}
    O -- Non --> P["Appliquer mode immédiatement"]
    O -- Oui --> Q["Saisir mot de passe du mode"]
    Q --> R{"Mot de passe valide ?"}
    R -- Non --> S["Refus + message erreur"]
    S --> G
    R -- Oui --> T["Appliquer nouveau mode"]
    I["Afficher infos application"] --> U["Retour au menu"]
    N --> U
    P --> U
    T --> U
    J --> U
    U --> V@{ label: "Paramètres actifs dans l'application" }
    C -- À propos --> I

    H@{ shape: rect}
    V@{ shape: rect}
     A:::start
     B:::action
     C:::decision
     D:::action
     E:::action
     F:::action
     G:::action
     H:::action
     J:::action
     K:::decision
     L:::warning
     M:::action
     N:::action
     O:::decision
     P:::action
     Q:::action
     R:::decision
     S:::warning
     T:::action
     I:::action
     U:::action
     V:::result
    classDef start fill:#0ea5e9,stroke:#0369a1,color:#ffffff,stroke-width:2px
    classDef action fill:#e2e8f0,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    classDef decision fill:#fef3c7,stroke:#d97706,color:#78350f,stroke-width:2px
    classDef result fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:2px
    classDef warning fill:#fee2e2,stroke:#dc2626,color:#7f1d1d,stroke-width:1.8px      
```
## 10) Workflow Monitoring

```mermaid
---
config:
  theme: base
  flowchart:
    nodeSpacing: 42
    rankSpacing: 58
    curve: linear
  themeVariables:
    fontSize: 13px
    lineColor: '#334155'
    primaryTextColor: '#0f172a'
    fontFamily: Inter,Segoe UI,Arial
  layout: fixed
---
flowchart TB
    A["Ouvrir Monitoring depuis Home"] --> B["Charger états appareils"]
    B --> C{"Données disponibles ?"}
    C -- Non --> D["Afficher état vide / non connecté"]
    C -- Oui --> F["Afficher grille des appareils"]
    F --> G{"Action utilisateur ?"}
    G -- Aucune --> H["Mise à jour passive en temps réel"]
    H --> F
    G -- ON/OFF --> I["Envoyer commande MQTT"]
    G -- Couleur/Luminosité --> J["Ouvrir contrôle lampe"]
    J --> I
    I --> K{"Retour MQTT reçu ?"}
    K -- Non --> L["Afficher délai / réessayer"]
    L --> I
    K -- Oui --> M["Mettre à jour état local"]
    M --> N["Rafraîchir carte appareil"]
    N --> O["Statut visible et cohérent"]
    D --> B

     A:::start
     B:::action
     C:::decision
     D:::warning
     F:::action
     G:::decision
     H:::action
     I:::action
     J:::action
     K:::decision
     L:::warning
     M:::action
     N:::action
     O:::result
    classDef start fill:#0ea5e9,stroke:#0369a1,color:#ffffff,stroke-width:2px
    classDef action fill:#e2e8f0,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    classDef decision fill:#fef3c7,stroke:#d97706,color:#78350f,stroke-width:2px
    classDef result fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:2px
    classDef warning fill:#fee2e2,stroke:#dc2626,color:#7f1d1d,stroke-width:1.8px
```

---

## 11) Workflow TEST.MQTT

```mermaid
---
config:
  theme: base
  flowchart:
    nodeSpacing: 42
    rankSpacing: 58
    curve: linear
  themeVariables:
    fontSize: 13px
    lineColor: '#334155'
    primaryTextColor: '#0f172a'
    fontFamily: Inter,Segoe UI,Arial
  layout: fixed
---
flowchart TB
    A["Ouvrir TEST.MQTT depuis Home"] --> B["Initialiser page de diagnostic"]
    B --> C{"MQTT connecté ?"}

    C -- Non --> D["Afficher statut déconnecté"]
    D --> E["Action: Reconnecter"]
    E --> F["Tentative de connexion MQTT"]
    F --> C

    C -- Oui --> G["Afficher contrôles MQTT"]
    G --> H{"Type d'action"}

    H -- Publier message --> I["Saisir topic + payload"]
    I --> J["Envoyer publication"]
    J --> K{"Envoi réussi ?"}
    K -- Non --> L["Toast erreur / garder saisie"]
    L --> I
    K -- Oui --> M["Toast succès"]

    H -- Lire activité --> N["Afficher historique messages"]
    N --> O{"Nouveaux messages ?"}
    O -- Oui --> P["Actualiser liste en direct"]
    P --> N
    O -- Non --> N

    H -- Commandes rapides --> Q["Envoyer commande prédéfinie"]
    Q --> K

    M --> R["État et historique cohérents"]
    N --> R

     A:::start
     B:::action
     C:::decision
     D:::warning
     E:::action
     F:::action
     G:::action
     H:::decision
     I:::action
     J:::action
     K:::decision
     L:::warning
     M:::result
     N:::action
     O:::decision
     P:::action
     Q:::action
     R:::result
    classDef start fill:#0ea5e9,stroke:#0369a1,color:#ffffff,stroke-width:2px
    classDef action fill:#e2e8f0,stroke:#64748b,color:#0f172a,stroke-width:1.5px
    classDef decision fill:#fef3c7,stroke:#d97706,color:#78350f,stroke-width:2px
    classDef result fill:#dcfce7,stroke:#16a34a,color:#14532d,stroke-width:2px
    classDef warning fill:#fee2e2,stroke:#dc2626,color:#7f1d1d,stroke-width:1.8px
```

---