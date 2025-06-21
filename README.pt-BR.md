# LiveWalls

<p align="center">
  <img src="icon_asset/icono-macOS-Default-1024x1024@2x.png" alt="LiveWalls" width="200" height="200">
</p>

## 📖 Leia em outras línguas

[🇺🇸 English](README.en.md) | [🇪🇸 Español](README.es.md) | [🇫🇷 Français](README.fr.md) | [🇩🇪 Deutsch](README.de.md) | [🇮🇹 Italiano](README.it.md)

[🇯🇵 日本語](README.ja.md) | [🇰🇷 한국어](README.ko.md) | [🇧🇷 Português](README.pt-BR.md) | [🇨🇳 简体中文](README.zh-CN.md) | [🇹🇼 繁體中文](README.zh-TW.md)

---

Uma aplicação nativa do macOS para usar vídeos como papéis de parede dinâmicos.

## 🎥 O que é o LiveWalls?

**LiveWalls** permite transformar qualquer vídeo MP4 ou MOV em um papel de parede dinâmico para macOS. Os vídeos se adaptam perfeitamente à sua tela, funcionam em múltiplos monitores e sempre permanecem em segundo plano sem interferir no seu trabalho.

## ✨ Funcionalidades

- 🎬 **Suporte a vídeos MP4 e MOV**
- 📱 **Escalonamento inteligente**: Vídeos se ajustam automaticamente à sua tela
- 🖥️ **Múltiplas telas**: Funciona em todos os displays conectados
- 🏢 **Todas as áreas de trabalho**: Exibe em todos os espaços de workspace do macOS
- 👻 **Execução em segundo plano**: Não interfere com outras aplicações
- 🎛️ **Interface gráfica**: Gerenciamento visual de vídeos com miniaturas
- 🔄 **Reprodução em loop**: Vídeos repetem automaticamente
- 📍 **Menu da barra de status**: Controle rápido pela barra de menu
- 🚀 **Início automático**: Opção para iniciar com o sistema
- ⚙️ **Persistência**: Lembra do seu último papel de parede na reinicialização

## 🎮 Uso

### 1. Adicionar Vídeos

- Clique no botão "+" para selecionar vídeos
- Arraste arquivos MP4 ou MOV para a aplicação

### 2. Definir Papel de Parede

- Selecione um vídeo da lista
- Clique em "Definir como Papel de Parede"
- Aproveite seu fundo dinâmico!

### 3. Controle Rápido

- Use o ícone da barra de menu para controlar a reprodução
- Ativar/desativar início automático
- Abrir o app do segundo plano

## 📋 Requisitos

- macOS 14.0 (Sonoma) ou posterior
- Xcode 15.0 ou posterior (para compilar do código-fonte)

## ⚙️ Instalação

### 📥 Baixar Release (Recomendado)

Baixe a versão compilada mais recente das [GitHub Releases](https://github.com/fparrav/LiveWalls/releases/latest).

**⚠️ Importante:** Como o app não está assinado com um certificado Apple Developer, você precisará permitir manualmente sua execução.

#### Método 1: Comando do Terminal (Recomendado)

```bash
sudo xattr -rd com.apple.quarantine /caminho/para/LiveWalls.app
```

#### Método 2: Configurações do Sistema

1. Tente abrir o LiveWalls (um aviso de segurança aparecerá)
2. Vá para **Configurações do Sistema** → **Privacidade e Segurança**
3. Procure por "LiveWalls foi bloqueado" e clique em **"Abrir Mesmo Assim"**

#### Método 3: Clique com botão direito

1. **Clique com botão direito** no LiveWalls.app
2. Selecione **"Abrir"** do menu de contexto
3. Clique em **"Abrir"** no diálogo de segurança

### 🛠️ Compilar do Código-fonte

   ```bash
   git clone https://github.com/fparrav/LiveWalls.git
   cd LiveWalls
   ```

   ```bash
   ./build.sh
   ```

   O app compilado estará na pasta `build/Debug/`.

## 🔒 Segurança e Privacidade

### Permissões necessárias

- **Acessibilidade**: Para definir o papel de parede na área de trabalho
- **Arquivos e Pastas**: Para acessar vídeos selecionados

**LiveWalls é um projeto 100% código aberto** que você pode revisar e compilar você mesmo.

### Por que o app não está assinado?

- A associação Apple Developer custa $99 USD/ano
- Este é um projeto gratuito sem propósito comercial
- Você pode verificar a segurança revisando o código-fonte

### Como verificar a segurança

1. **Revise o código-fonte** neste repositório
2. **Compile você mesmo** usando Xcode
3. **Inspecione o build** antes de executá-lo

## 🚀 Desenvolvimento

Para desenvolvedores que querem contribuir ou entender melhor o código, veja a documentação de desenvolvimento.

## 📄 Licença

Este projeto está sob a Licença MIT. Veja o arquivo `LICENSE` para detalhes.

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor:

1. Fork o repositório
2. Crie uma branch de funcionalidade
3. Faça suas alterações
4. Envie um pull request

## ⭐ Suporte

Se você gosta do LiveWalls, por favor dê uma estrela no GitHub! Isso ajuda outros usuários a descobrir o projeto.

---

**Feito com ❤️ para a comunidade macOS**
