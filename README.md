# UltraClaw OS — Build System

Desenvolva no Windows, o build acontece automaticamente no GitHub.

## Como funciona

```
Você faz push no GitHub
        │
        ▼
GitHub Actions (VM Ubuntu gratuita)
        │
        ├── Baixa Ubuntu 24.04 ISO base
        ├── Extrai o filesystem (squashfs)
        ├── Entra no chroot
        ├── Roda install.sh (instala CLAW-OS)
        ├── Instala o UltraClaw theme
        ├── Recompacta o filesystem
        └── Gera ultraclaw-os-VERSAO-amd64.iso
                │
                ▼
        Disponível para download
        em Actions > Artifacts
```

## Estrutura do repositório

```
ultraclaw-os/
├── .github/
│   └── workflows/
│       └── build-iso.yml     ← pipeline de build
├── scripts/
│   └── install.sh            ← instalador do CLAW-OS
├── theme/
│   ├── install-theme.sh      ← instala Plymouth + GRUB + wallpapers
│   ├── plymouth/
│   │   ├── ultraclaw.script
│   │   └── ultraclaw.plymouth
│   └── grub/
│       └── theme.txt
└── README.md
```

## Fazendo uma build

### Build automático (recomendado)
Qualquer push na branch `main` dispara o build automaticamente.

```bash
git add .
git commit -m "feat: atualiza tema do boot"
git push origin main
# Acesse: github.com/SEU-USUARIO/ultraclaw-os/actions
```

### Build manual (sem push)
1. Acesse a aba **Actions** no GitHub
2. Clique em **Build UltraClaw ISO**
3. Clique em **Run workflow**

### Baixar a ISO após o build
1. Acesse **Actions** → clique no build mais recente
2. Role até **Artifacts**
3. Clique no arquivo `.iso` para baixar

## Lançar uma versão oficial

```bash
git tag v1.0.0
git push origin v1.0.0
```

Isso cria automaticamente uma **GitHub Release** com a ISO e o checksum SHA256 disponíveis para download público.

## Tempo estimado de build

| Etapa                    | Tempo     |
|--------------------------|-----------|
| Download da ISO base     | ~5 min (cacheada após 1ª vez) |
| Extração do squashfs     | ~3 min    |
| install.sh no chroot     | ~15 min   |
| Recompactar squashfs     | ~15 min   |
| Gerar ISO final          | ~2 min    |
| **Total**                | **~40 min** (primeira vez) |
| **Total com cache**      | **~35 min** |

## Verificar a ISO baixada

```bash
sha256sum -c ultraclaw-os-v1.0.0-amd64.iso.sha256
```

## Gravar em pendrive (Windows)

1. Baixe o [Balena Etcher](https://etcher.balena.io/)
2. Selecione a ISO
3. Selecione o pendrive (mínimo 4GB)
4. Flash!
