<html><body><h1 style="font-size:50px;color:blue;">WEZVA TECHNOLOGIES (ADAM) | <font style="color:red;"> www.RimBox.fr | <font style="color:green;"> +91-9739110917 </h1>
<h1> Subscribe to our youtube channel: 
<a href="https://www.youtube.com/c/DevOpsLearnEasy">https://www.youtube.com/c/DevOpsLearnEasy</a> </h1>
</body></html>
  
# TROUBLESHOOT HTTP ERROR CODES IN KUBERNETES

## 301: Ingress and pod network work perfectly, but the system instructs the client that the requested URL has permanently moved to a new destination.
- An HTTP 301 Moved Permanently response is not actually an error. It is a redirect command telling the client (QA browser, mobile app, or automation script) that the URL they requested has permanently changed to a new location, and they must update their bookmarks or API configurations.

## 401: Ingress and pod network work perfectly, but the application or gateway rejects the request because valid authentication credentials are missing or invalid.
- An HTTP 401 Unauthorized error means that the entire networking path (Load Balancer -> Ingress -> Service -> Pod) is completely functional and the endpoint exists, but the request was rejected because it lacks valid authentication credentials.

## 404: Ingress and pod network work perfectly, but the requested endpoint path or database resource does not exist anywhere on the system.
- In our Kubernetes architecture, an HTTP 404 Not Found means the entire infrastructure path—Load Balancer, Ingress controller, Service network, and the Pod's container—worked perfectly. However, the client requested a path or resource that does not exist. 
- Depending on where the 404 is generated, it means one of two things:
The Ingress Controller 404: The URL routing rule doesn't exist in your Kubernetes Ingress YAML.
The Application Pod 404: The routing rule exists in Kubernetes, but your microservice code (e.g., Express, Spring Boot, FastAPI) has no matching code route or database record for that endpoint.

## 500: The pod and container network work flawlessly, but your software code threw an unhandled exception.
- An HTTP 500 Internal Server Error means your traffic successfully passed through the Ingress controller, safely navigated the Service network, reached the pod, and entered your application code—but your application code itself crashed while processing the request.

## 502: Ingress found the pod, but the container/network layer broke.
- 502 Bad Gateway means that your traffic successfully passed through the Ingress controller and did manage to reach the pod, but the pod sent back a completely invalid response, or abruptly cut the connection

## 503: Ingress couldn't find a pod.

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
