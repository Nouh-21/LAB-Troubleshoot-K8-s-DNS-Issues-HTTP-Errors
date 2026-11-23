# Kubernetes HTTP Troubleshooting Lab

Ce laboratoire reproduit les principaux codes de réponse HTTP dans un cluster Kubernetes existant. Chaque scénario utilise un manifeste unique pour déployer une application Python sur Docker Desktop, un Service, un Ingress NGINX et un comportement HTTP spécifique.

## Architecture

```text
Navigateur ou curl
       |
       | http://localhost:80
       v
kubectl port-forward
       |
       v
Service ingress-nginx-controller
       |
       v
Contrôleur NGINX Ingress
       |
       v
Ingress wezva-ingress
       |
       v
Service wezva-service
       |
       v
Endpoint du Pod wezva-deployment
       |
       v
Python HTTP Server :8080
```

## Prérequis

- Docker Desktop avec Kubernetes activé
- `kubectl`
- Bash ou Git Bash
- Accès au contexte Docker Desktop
- Le port local `80` disponible

Depuis le dossier du projet :

```bash
kubectl config current-context
kubectl cluster-info
./runme.sh --setup
```

Le script conserve le cluster existant. Il installe ou vérifie le contrôleur NGINX, déploie le scénario sain 200, crée le port-forward et affiche les ressources actives.

## Commandes principales

| Commande | Action |
|---|---|
| `./runme.sh --setup` | Prépare le contrôleur et déploie le scénario 200 |
| `./runme.sh --scenario-1` | Déploie HTTP 200 |
| `./runme.sh --scenario-2` | Déploie HTTP 301 |
| `./runme.sh --scenario-3` | Déploie HTTP 401 |
| `./runme.sh --scenario-4` | Déploie HTTP 404 |
| `./runme.sh --scenario-5` | Déploie HTTP 500 |
| `./runme.sh --scenario-6` | Déploie HTTP 502 |
| `./runme.sh --scenario-7` | Déploie HTTP 503 |
| `./runme.sh --cleanup` | Supprime les ressources applicatives |
| `./runme.sh --downOff` | Supprime également NGINX et les ressources locales |

Variables possibles :

```bash
KUBE_CONTEXT=docker-desktop
NAMESPACE=default
HTTP_PORT=80
HTTPS_PORT=8443
```

## Scénarios

### Scénario 1 — HTTP 200 OK

**Manifeste :** `lab/1-healthy-200.yaml`

Le Pod répond normalement et confirme que toute la chaîne réseau est opérationnelle.

```bash
./runme.sh --scenario-1
curl -iv http://localhost:80/
```

Résultat attendu :

```text
HTTP/1.1 200 OK
```

Vérifications :

```bash
kubectl -n default get pods,services,ingress,endpoints
kubectl -n default describe service wezva-service
```

### Scénario 2 — HTTP 301 Moved Permanently

**Manifeste :** `lab/2-redirect-301.yaml`

Le contrôleur NGINX utilise une annotation de redirection permanente vers `https://wezvatech.com`.

```bash
./runme.sh --scenario-2
curl -IL http://localhost:80/
```

Vérifications :

```bash
kubectl -n default get ingress wezva-ingress -o yaml
kubectl -n default describe ingress wezva-ingress
```

Correctif :

```bash
kubectl -n default annotate ingress wezva-ingress \
  nginx.ingress.kubernetes.io/permanent-redirect-
```

### Scénario 3 — HTTP 401 Unauthorized

**Manifeste :** `lab/3-client-401.yaml`

L’application exige un jeton `Bearer` valide.

Sans authentification :

```bash
curl -iv http://localhost:80/ OR curl -iv http://localhost
```

Avec authentification :

```bash
curl -iv -H 'Authorization: Bearer secret-token' http://localhost:80/
```

Résultat attendu :

```text
HTTP/1.1 401 Unauthorized
HTTP/1.1 200 OK
```

Vérifications :

```bash
kubectl -n default get pods,services,ingress
kubectl -n default logs -l app=wezva-app --tail=50
```

### Scénario 4 — HTTP 404 Not Found

**Manifeste :** `lab/4-client-404.yaml`

Une route valide est disponible sur `/healthz`. Les autres routes renvoient une erreur 404 applicative.

```bash
./runme.sh --scenario-4
curl -iv http://localhost:80/
curl -iv http://localhost:80/healthz
```

Diagnostics :

```bash
kubectl -n default describe ingress wezva-ingress
kubectl -n default logs -l app=wezva-app --tail=50
```

Un 404 provenant de NGINX peut aussi indiquer une `IngressClass`, une règle de route ou un backend introuvable.

### Scénario 5 — HTTP 500 Internal Server Error

**Manifeste :** `lab/5-server-500.yaml`

L’application attend une variable `DATABASE_URL`. Lorsqu’elle est absente, l’application retourne 500.

```bash
./runme.sh --scenario-5
curl -iv http://localhost:80/
kubectl -n default logs -l app=wezva-app --tail=100
```

Résultat attendu :

```text
HTTP/1.1 500 Internal Server Error
```

Correctif :

```bash
kubectl -n default set env deployment/wezva-deployment \
  DATABASE_URL=postgres://user:pass@db:5432/wezva
kubectl -n default rollout status deployment/wezva-deployment
```

### Scénario 6 — HTTP 502 Bad Gateway

**Manifeste :** `lab/6-badgateway-502.yaml`

Le Service pointe volontairement vers le port `9999`, alors que le conteneur écoute sur `8080`.

```bash
./runme.sh --scenario-6
curl -iv http://localhost:80/
```

Diagnostics :

```bash
kubectl -n default describe service wezva-service
kubectl -n default get endpoints wezva-service
kubectl -n ingress-nginx logs deployment/ingress-nginx-controller --tail=50
```

Correctif :

```bash
kubectl -n default patch service wezva-service --type='json' \
  -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":8080}]'
```

### Scénario 7 — HTTP 503 Service Unavailable

**Manifeste :** `lab/7-serviceunavailable-503.yaml`

Le scénario utilise initialement un Service dont le sélecteur ne correspond à aucun Pod actif.

```bash
./runme.sh --scenario-7
curl -iv http://localhost:80/
```

Diagnostics :

```bash
kubectl -n default get pods --show-labels
kubectl -n default get endpoints wezva-service
kubectl -n default describe service wezva-service
```

Correctif :

```bash
kubectl -n default patch service wezva-service \
  -p '{"spec":{"selector":{"app":"wezva-app"}}}'

kubectl -n default rollout restart deployment/wezva-deployment
kubectl -n default rollout status deployment/wezva-deployment --timeout=120s
kubectl -n default get endpoints wezva-service
```

## Diagnostic général

```bash
kubectl get nodes
kubectl -n ingress-nginx get pods,services
kubectl -n default get deployments,pods,services,ingress,endpoints
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
kubectl -n default describe ingress wezva-ingress
kubectl -n default describe service wezva-service
kubectl -n default get events --sort-by='.lastTimestamp'
```

## Résolution du 404 NGINX

Si NGINX retourne un 404 générique alors que les ressources existent :

1. Vérifiez que `IngressClass/nginx` existe :

```bash
kubectl get ingressclass nginx
```

2. Vérifiez que l’Ingress utilise cette classe :

```yaml
spec:
  ingressClassName: nginx
```

3. Vérifiez le Service et ses endpoints :

```bash
kubectl -n default get service wezva-service endpoints wezva-service
```

4. Vérifiez les journaux du contrôleur :

```bash
kubectl -n ingress-nginx logs deployment/ingress-nginx-controller --tail=100
```

## Accès HTTP et HTTPS

HTTP :

```bash
curl -iv http://localhost:80/
```

HTTPS :

```bash
curl -kiv https://localhost:8443/
```

Le port-forward est géré par `runme.sh` :

```text
localhost:80  -> ingress-nginx-controller:80
localhost:8443 -> ingress-nginx-controller:443
```

## Nettoyage

Nettoie uniquement les ressources applicatives :

```bash
./runme.sh --cleanup
```

Supprime les applications, le contrôleur NGINX, les RBAC, l’IngressClass et le dossier `.runtime` :

```bash
./runme.sh --downOff
```

Le cluster Docker Desktop Kubernetes n’est pas supprimé.


# COMPTE RENDU — Correction du 404 NGINX

## Root cause

Lors des premiers tests, `http://localhost:8080/` retournait le 404 générique suivant :

```text
HTTP/1.1 404 Not Found
<center>nginx</center>
```

Les ressources applicatives étaient pourtant opérationnelles :

- Le Pod `wezva-deployment` était `Running` et disponible avec `1/1`.
- Le Service `wezva-service` était correctement configuré.
- Son endpoint contenait l'adresse du Pod sur le port `8080`.
- Un test direct depuis le Pod retournait `200 OK`.
- L'Ingress `wezva-ingress` référençait la classe `nginx`.

La véritable cause était que la ressource Kubernetes `IngressClass` nommée `nginx` n'existait pas. Le contrôleur NGINX ignorait donc l'Ingress `wezva-ingress` et répondait avec son propre 404 par défaut.

Les journaux du contrôleur confirmaient cette situation :

```text
Ignoring ingress because of error while validating ingress class
ingress="default/wezva-ingress"
error="no object matching key \"nginx\" in local store"
```

## Correctifs apportés

Le manifeste `lab/ingress_nginx_kind.yaml` a été corrigé pour Docker Desktop :

- Suppression du sélecteur Kind `ingress-ready=true`, absent du nœud Docker Desktop.
- Ajout du `ServiceAccount` `ingress-nginx`.
- Ajout du Service `ingress-nginx-controller` avec les ports HTTP `80` et HTTPS `443`.
- Ajout de l'`IngressClass` requise :

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/ingress-nginx
```

- Ajout des probes `readinessProbe` et `livenessProbe` sur `/healthz`.
- Ajout des règles RBAC nécessaires au contrôleur.
- Application du manifeste corrigé avec `kubectl apply`.
- Redémarrage du Deployment du contrôleur afin qu'il recharge la nouvelle configuration.
- Relance du port-forward sur les ports locaux `8080` et `8443`.

## Résultat

Après correction, le contrôleur accepte l'Ingress et route le trafic vers le backend :

```text
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8

🚀 200 OK: Welcome to WezvaTech K8s Lab Baseline!
```

Commandes de vérification :

```bash
kubectl get ingressclass nginx
kubectl -n ingress-nginx get pods,services
kubectl -n default get ingress,pods,services,endpoints
curl -i http://localhost:8080/
```
