+++
title = 'Atualizações --- Homelab, Kubernetes e este blog'
date = 2025-04-09
slug = 'atualizacoes-homelab-com-kubernetes'
draft = false
categories = ["homelab"]
tags = ["homelab", "kubernetes", "k3s", "arch linux"]
+++

Um conto sobre como retornei às atividades do blog após um tempão, implementei um homelab novo com um iMac 2011 e Kubernetes (k3s), e decidi migrar a infra do blog do GitHub Pages para meu cluster Kubernetes.
<!--more-->
---

Após sumir por um período prolongado, *eu vim fazer um anuncio*: "Notas do Cyberespaço" está de volta! (Prometo ser mais ativa dessa vez XD)

Não estou muito afim de elaborar sobre meu sumiço e seus motivos, vocês não precisam ouvir desculpas esfarrapadas --- o importante é que tomei vergonha na cara e estou de volta.

Depois de meses longe de qualquer projeto técnico pessoal, decidi retomar o homelabbing como hobby. Precisava de algo para ocupar a cabeça ("mente vazia é ofícina do diabo", minha vó dizia) e as mãos, e nada melhor do que ressuscitar hardware que não uso mais e montar uma infra legal, só para diversificar um pouco minha rotina.

Peguei meu antigo iMac 2011 com 32 GB RAM DDR3 e, ao invés da minha instalação usual do Proxmox VE ou do VMware ESXi, resolvi experimentar com Kubernetes.

## Escolhendo o SO

Para instalar o Kubernetes, eu tinha algumas opções de sistema para usar no host, as que mais considerei foram:

1. **NixOS + k3s** --- uma boa escolha porque mistura uma distro que já uso no dia-a-dia com um Kubernetes "*lightweight*" (o k3s)
2. **Arch Linux + k3s** --- também é uma boa escolha porque, apesar de não usar mais tanto na minha rotina, tenho muito mais anos de experiência com Arch Linux do que com NixOS
3. **Talos Linux** --- uma opção interessante pela segurança e dizem possuir uma reproducibilidade semelhante ao do NixOS, mas logo descartei porque usa k8s (Kubernetes padrão) ao invés do k3s, e temo do k8s não rodar bem com o iMac como unico node + os workloads que pretendo rodar nele

Não tive boa experiência com k3s no NixOS antes, então decidi ir com Arch Linux dessa vez. Ainda pretendo adicionar nodes NixOS ao cluster no futuro, porém.

Vou pular a parte onde explico a instalação do Arch --- é um monte de lero-lero redundante só pra dizer que conectei a máquina no wifi e rodei `archinstall`... Vamos direto para o que interessa.

## Instalando o k3s

Coisa rápida e simples --- baixa o `git` e instala o pacote `k3s-bin` do AUR:

```bash
# no servidor
sudo pacman -Sy git
```

```bash
# no servidor
pushd $(mktemp -d)
git clone --depth=1 https://aur.archlinux.org/k3s-bin.git
cd k3s-bin
makepkg -si
cd ..
rm -rfv ./k3s-bin
popd
```

Agora, só resta ativar o serviço e copiar a *kube config* para minha máquina:

```bash
# no servidor
sudo systemctl enable k3s
sudo systemctl start k3s
```

```bash
# no servidor
sudo cp -v /etc/rancher/k3s/k3s.yaml ~/k3s.yaml
sudo chown binaryskunk:users ~/k3s.yaml

# na minha maquina
scp binaryskunk@algebra:/home/binaryskunk/k3s.yaml ~/.kube/config
nvim ~/.kube/config # trocar o IP do servidor na configuração
```

Por fim, também adicionei o node Kubernetes a minha VPN pessoal no Tailscale:

```bash
# no servidor
sudo pacman -S tailscale
sudo systemctl enable tailscaled
sudo systemctl start tailscaled
sudo tailscale up
```

## Servidor DNS

Decidi inaugurar o cluster k3s instalando um servidor DNS [Pi-hole](https://pi-hole.net/) pra já ter como configurar domínios customizados para minha rede interna (não, eu não vou usar o MagicDNS do Tailscale).

Comecei criando o namespace `dns`, e um secret para guardar a senha de acesso ao painel web do Pi-hole.

```bash
kubectl create namespace dns
```

```yaml
# ./pihole-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: pihole-web
  namespace: dns
type: Opaque
data:
  ADMIN_PASS: "uma senha bem forte XD"
```

```bash
kubectl apply -f ./pihole-secret.yaml
shred -uzxv ./pihole-secret.yaml
```

Então, escrevo um manifesto YAML ditando a configuração que quero para o serviço DNS.

```yaml
# ./pihole-values.yaml
serviceDns:
  type: LoadBalancer
  loadBalancerIP: 192.168.0.134
doh:
  enabled: true
  pullPolicy: Always
  envVars: {
    DOH_UPSTREAM: "https://1.1.1.1/dns-query"
  }
ingress:
  enabled: true
  hosts:
  - dns.skunklab.local
serviceWeb:
  type: ClusterIP
  loadBalancerIP: 192.168.0.134
admin:
  enabled: true
  existingSecret: "pihole-web"
  passwordKey: "ADMIN_PASS"
```

E uso o manifesto para instalar o Pi-hole:

```bash
helm repo add mojo2600 https://mojo2600.github.io/pihole-kubernetes/
helm repo update
helm upgrade --install pihole --namespace dns mojo2600/pihole -f ./pihole-values.yaml
```

Adiciono `dns.skunklab.local [IP DO SERVIDOR]` ao meu `/etc/hosts` e acesso o painel web do Pi-hole, onde logo adiciono o mesmo registro DNS.

Finalmente, altero minha lista de servidores DNS para usar meu serviço de DNS:

```nix
networking = {
  dhcpcd.extraConfig = ''
    nohook resolv.conf
  '';

  nameservers = [
    "IP LOCAL DO SERVIDOR"
    "IP DO SERVIDOR NA VPN"
    "1.1.1.1"
    "8.8.8.8"
  ]
};
```

Já posso retirar o registro DNS do meu arquivo hosts, e pronto --- de agora em diante, criarei domínios locais para cada serviço que eu hospedar internamente.

## Gitea

Escrevi um arquivo `gitea-values.yaml` e usei ele para instalar o Gitea via Helm, após criar o namespace apropriado e adicionar seu repositório Helm respectivo.

```yaml
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: nginx
  hosts:
    - host: git.skunklab.local
      paths:
        - path: /
          pathType: Prefix
service:
  http:
    type: ClusterIP
    port: 80
    clusterIP: 10.43.14.16
  ssh:
    type: ClusterIP
    port: 22
    clusterIP: 10.43.14.17

gitea:
  config:
    server:
      SSH_DOMAIN: git.skunklab.local
    service:
      DISABLE_REGISTRATION: true
      SHOW_REGISTRATION_BUTTON: false
```

```bash
kubectl create namespace gitea
helm repo add gitea-charts https://dl.gitea.com/charts/
helm repo update
helm install gitea gitea-charts/gitea --namespace git -f ./gitea-values.yaml
```

## Harbor

Subir um registro de imagens docker (o Harbor) é similar a instalação anterior do Gitea: escreve arquivo values, cria namespace, adiciona o repositório Helm e instala.

```yaml
expose:
  type: ingress
  tls:
    enabled: true
    certSource: auto
  ingress:
    hosts:
      core: registry.skunklab.local
      notary: registry.skunklab.local
    annotations:
      kubernetes.io/ingress.class: nginx

externalURL: https://registry.skunklab.local

persistence:
  enabled: true
  persistentVolumeClaim:
    registry:
      size: 50Gi
    database:
      size: 5Gi
    redis:
      size: 1Gi

harborAdminPassword: "my!admin3pass"
```

Claro que troquei esta senha depois do deploy, né --- curiosos e script kiddies de plantão, nem tentem!

```bash
kubectl create namespace registry
helm repo add harbor https://helm.goharbor.io
helm repo update
helm install harbor harbor/harbor -f ./harbor-values.yaml -n registry
```


## Cloudflare Gateway

Uso o [Cloudflare Kubernetes Gateway](https://github.com/pl4nty/cloudflare-kubernetes-gateway) para expor serviços à Internet pública via proxy reversa Cloudflare.

Acho que não vale a pena parafrasear o que já está escrito no README do projeto... Instruções para uso e instalação estão lá.

## Migrando o blog para meu cluster Kubernetes

Depois de restaurar o tema clássico, criar um repositório no Gitea e trocar a origem do meu clone local para lá, ainda me faltavam algumas coisas para migrar meu blog do GitHub Pages para minha rede local:

1. Escrever um 'Dockerfile' para construir uma versão containerizada do meu site e publicá-la no meu registro. Decidi usar [Caddy](https://caddyserver.com/) ao invés de Nginx aqui, então também precisei escrever um `Caddyfile`.

```caddyfile
# Caddyfile
:80 {
  root * /usr/share/caddy
  file_server

  header {
    X-Frame-Options "SAMEORIGIN"
    X-XSS-Protection "1; mode=block"
    X-Content-Type-Options "nosniff"
    Content-Security-Policy "default-src 'self'; script-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self'; connect-src 'self';"
    Referrer-Policy "strict-origin-when-cross-origin"
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    -Server
  }

  encode gzip zstd

  handle_errors {
    @404 {
      expression {http.error.status_code} == 404
    }
    rewrite @404 /404.html
    file_server
  }
}
```

```dockerfile
# Dockerfile
FROM hugomods/hugo:nightly AS builder
WORKDIR /src
COPY . .
RUN hugo --gc --minify --noBuildLock

FROM caddy:2.9.1-alpine
WORKDIR /usr/share/caddy
COPY --from=builder /src/public /usr/share/caddy
COPY ./Caddyfile /etc/caddy/Caddyfile
```

```bash
docker build -t registry.skunklab.local/kernel32/blog:v3
```

2. Escrever um manifesto YAML para deploy da imagem `kernel32/blog:v3` no Kubernetes. Resolvi não fazer deploy também de um [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) porque não vi necessidade --- meu site já não recebe muito tráfego e boa parte dele já é respondido pelo cache da Cloudflare de qualquer jeito...

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kernel32
  labels:
    name: kernel32
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: caddy-config
  namespace: kernel32
data:
  Caddyfile: |
    # Um Caddyfile diferente do anterior, dessa vez voltado para deploy em produção mesmo
    {
      auto_https off
      admin off
    }

    :80 {
      root * /usr/share/caddy
      file_server

      header {
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        X-Content-Type-Options "nosniff"
        Content-Security-Policy "default-src 'self'; script-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self'; connect-src 'self';"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
      }

      encode gzip zstd

      handle_errors {
        @404 {
          expression {http.error.status_code} == 404
        }
        rewrite @404 /404.html
        file_server
      }

      log {
        output stdout
        format json
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kernel32-blog
  namespace: kernel32
spec:
  replicas: 2
  selector:
    matchLabels:
      app: kernel32-blog
  template:
    metadata:
      labels:
        app: kernel32-blog
    spec:
      containers:
      - name: kernel32-blog
        image: registry.skunklab.local/kernel32-blog/kernel32-blog:v3
        ports:
        - containerPort: 80
          name: http
        volumeMounts:
        - name: caddy-config
          mountPath: /etc/caddy/Caddyfile
          subPath: Caddyfile
        livenessProbe:
          httpGet:
            path: /
            port: http
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /
            port: http
          initialDelaySeconds: 5
          periodSeconds: 10
      volumes:
      - name: caddy-config
        configMap:
          name: caddy-config
---
apiVersion: v1
kind: Service
metadata:
  name: kernel32-blog
  namespace: kernel32
spec:
  selector:
    app: kernel32-blog
  ports:
  - port: 80
    targetPort: 80
    name: http
  type: ClusterIP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: kernel32-route
  namespace: kernel32
spec:
  parentRefs:
  - name: gateway
    namespace: cloudflare-gateway
  hostnames:
  - kernel32.xyz
  rules:
    - backendRefs:
      - name: kernel32-blog
        port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kernel32-network-policy
  namespace: kernel32
spec:
  podSelector:
    matchLabels:
      app: kernel32-blog
  policyTypes:
  - Egress
  egress: []
```

Após cumprir ambos os requisitos, posso finalmente fazer o deploy:

```bash
kubectl apply -f ./deploy/k8s.yaml
```

## Planos futuros

1. Meus stalkers de plantão já devem ter notado que este blog tinha uma pipeline CI/CD (`.github/workflows/hugo.yaml`) para deploy automático no GitHub Pages. Como migrei o website para minha rede local, a pipeline não funciona mais e tenho, atualmente, que fazer re-deploy do blog para cada update/post novo. Tentei replicar a mesma pipeline usando Gitea Actions mas logo descobri que ativar esta funcionalidade no Gitea quando hospedado em Kubernetes é um inferno :skull:. Preciso arranjar um jeito de criar pipelines CI/CD novamente.

2. Tenho um PC gamer antigo e um servidor chassis SuperMicro que gostaria de adicionar como nodes ao meu cluster Kubernetes mas não posso deixar eles rodando 24/7 porque minha conta de energia elétrica já vem uma fortuna todo mês e eu não sou rica. Então preciso planejar uma infra onde seja possível rodar serviços "criticos" (como este blog) no iMac (node atual) e delegar pods para coisas tipo big data processing (estou lentamente me tornando uma acumuladora digital) e demais operações que exigam alto processamento para o PC gamer, e subir tarefas recorrentes de backup para o servidor chassis e usá-lo como armazenamento frio (ele tem uma controladora RAID, então seria bem útil como NAS).

3. Preciso subir logo uma wiki interna para documentar operações, playbooks e notas no meu homelab. Experimentei o [Wiki.js](https://js.wiki/) e não curti tanto, agora penso em hospedar o [Outline](https://www.getoutline.com/) mas ainda não o fiz porque ele me obriga a também hospedar um provedor de identidade para SSO e eu estou com muita preguiça para fazer isto agora.

4. Quero brincar com monitoramento e SIEM, pretendo subir instancias de ferramentas desses naipes em breve.

## Conclusão

Obrigada por ler! Prometo >>tentar<< ser mais ativa por aqui dessa vez, então... Fiquem ligados para os próximos posts e projetos!

Bye bye. :purple_heart:
