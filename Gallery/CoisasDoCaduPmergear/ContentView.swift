//
//  ContentView.swift
//  DaVinci
//

import SwiftUI
import RealityKit

struct moveCamera: View {

    // MARK: - Estado

    @State private var cameraEmCima = false
    @State private var camera = PerspectiveCamera()

    @State private var caixas: Entity?
    @State private var caixasAbertas = false
    @State private var animandoCaixas = false

    // MARK: - Configuração da câmera

    private let posicaoPadrao: SIMD3<Float> = [-1.5, 2.5, -2]
    private let posicaoEmCima: SIMD3<Float> = [-0.5, 1.5, 0]
    private let alvoDoOlhar: SIMD3<Float> = [0, 1.5, 0]   // ajuste para o centro do seu quarto
    private let alvoDoOlhar2: SIMD3<Float> = [2, 1.25, 0]

    // MARK: - Configuração das caixas

    private let anguloAbertura: Float = .pi * 0.6   // ~108°; troque o sinal se a aba for para dentro
    private let duracaoAbertura: Double = 1.0

    // MARK: - View

    var body: some View {
        ZStack {
            RealityView { content in
                // A câmera é virtual (nossa), não a do aparelho
                content.camera = .virtual

                // Quarto
                do {
                    let quarto = try await Entity(named: "BaseCenario 2")

                    // O .usdz traz uma câmera própria que brigaria com a nossa
                    removerCameras(de: quarto)

                    content.add(quarto)

                    //aplicarCores(em: quarto)
                } catch {
                    print("Erro ao carregar o quarto:", error)
                }

                // Caixas
                do {
                    let caixasEntity = try await Entity(named: "CaixasApenas(2)")

                    removerCameras(de: caixasEntity)

                    content.add(caixasEntity)
                    caixas = caixasEntity

                    diagnosticarCaixas(caixasEntity)
                } catch {
                    print("Erro ao carregar as caixas", error)
                }

                // Luz
                let luz = PointLight()
                luz.light.intensity = 100_0
                luz.light.color = .systemRed
                content.add(luz)

                // Câmera: posiciona e já aponta para o alvo
                camera.look(at: alvoDoOlhar, from: posicaoPadrao, relativeTo: nil)
                content.add(camera)
            }
            .ignoresSafeArea()

            VStack {
                Text("Dentro do Quarto")
                    .font(.headline)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)

                Spacer()

                Button(caixasAbertas ? "Fechar caixas" : "Abrir caixas") {
                    alternarCaixas()
                }
                .buttonStyle(.borderedProminent)
                .disabled(animandoCaixas || caixas == nil)
                .padding(.bottom, 32)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            cameraEmCima.toggle()
        }
        // Roda só quando o valor muda, então não reinicia a animação à toa
        .onChange(of: cameraEmCima) { _, novoValor in
            moverCamera(emCima: novoValor,
                        novoOlhar: novoValor ? alvoDoOlhar2 : alvoDoOlhar)
        }
    }

    // MARK: - Câmera

    private func moverCamera(emCima: Bool, novoOlhar: SIMD3<Float>) {
        let posicao = emCima ? posicaoEmCima : posicaoPadrao
        let destino = transformOlhando(de: posicao, para: novoOlhar)

        // Interpola posição e rotação juntas, em 2 segundos
        camera.move(
            to: destino,
            relativeTo: nil,
            duration: 2.0,
            timingFunction: .easeInOut
        )
    }

    /// look(at:) é instantâneo, então calculamos o transform de destino
    /// numa entidade temporária e deixamos o move(to:) fazer a animação.
    private func transformOlhando(de posicao: SIMD3<Float>,
                                  para alvo: SIMD3<Float>) -> Transform {
        let direcao = simd_normalize(alvo - posicao)

        // Olhando (quase) reto para cima ou para baixo, o up padrão fica ambíguo
        let quaseVertical = abs(direcao.y) > 0.99
        let up: SIMD3<Float> = quaseVertical
            ? [0, 0, direcao.y < 0 ? -1 : 1]
            : [0, 1, 0]

        let temporaria = Entity()
        temporaria.look(at: alvo, from: posicao, upVector: up, relativeTo: nil)
        return temporaria.transform
    }

    // MARK: - Caixas

    /// Abre ou fecha todas as caixas de uma vez.
    private func alternarCaixas() {
        guard let caixas else { return }

        let abrir = !caixasAbertas
        caixasAbertas = abrir
        animandoCaixas = true

        let de: Float = abrir ? 0 : anguloAbertura
        let ate: Float = abrir ? anguloAbertura : 0

        for caixa in encontrarCaixas(em: caixas) {
            for aba in abasDe(caixa) {
                animarAba(aba, de: de, ate: ate, duracao: duracaoAbertura)
            }
        }

        // Libera o botão quando a animação termina
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duracaoAbertura + 0.1))
            animandoCaixas = false
        }
    }

    /// Gira o osso da aba em torno do próprio eixo X (a dobradiça).
    /// `inicio` e `fim` são ângulos em radianos em relação à pose de repouso (0 = fechada).
    @MainActor
    private func animarAba(_ aba: Entity, de inicio: Float, ate fim: Float, duracao: Double) {
        guard let dono = acharPoses(em: aba),
              let pose = dono.components[SkeletalPosesComponent.self]?.poses.default,
              let indice = pose.jointNames.firstIndex(where: { $0.hasSuffix("Bone") })
        else {
            print("Sem esqueleto utilizável em:", aba.name)
            return
        }

        // Recupera a rotação de repouso removendo o ângulo atual,
        // assim abrir e fechar várias vezes não acumula erro.
        let atual = pose.jointTransforms[indice].rotation
        let repouso = atual * simd_quatf(angle: -inicio, axis: [1, 0, 0])

        Task { @MainActor in
            let passos = 60
            for i in 0...passos {
                let t = Float(i) / Float(passos)
                let suave = t * t * (3 - 2 * t)                    // ease in/out
                let angulo = inicio + (fim - inicio) * suave

                if var componente = dono.components[SkeletalPosesComponent.self] {
                    componente.poses.default?.jointTransforms[indice].rotation =
                        repouso * simd_quatf(angle: angulo, axis: [1, 0, 0])
                    dono.components.set(componente)
                }

                try? await Task.sleep(for: .seconds(duracao / Double(passos)))
            }
        }
    }

    /// Todas as entidades "P3_Caixa_M..." (uma por caixa).
    private func encontrarCaixas(em entity: Entity) -> [Entity] {
        var resultado: [Entity] = []
        if entity.name.hasPrefix("P3_Caixa_M") {
            resultado.append(entity)
        }
        for filho in entity.children {
            resultado += encontrarCaixas(em: filho)
        }
        return resultado
    }

    /// As duas abas (Esquerda e Direita) de uma caixa.
    private func abasDe(_ caixa: Entity) -> [Entity] {
        caixa.children.filter {
            $0.name.contains("Esquerda") || $0.name.contains("Direita")
        }
    }

    /// Procura, na árvore, a entidade que recebeu o esqueleto.
    private func acharPoses(em entity: Entity) -> Entity? {
        if entity.components[SkeletalPosesComponent.self] != nil { return entity }
        for filho in entity.children {
            if let achado = acharPoses(em: filho) { return achado }
        }
        return nil
    }

    /// Imprime no console o que o RealityKit importou. Útil para conferir nomes.
    private func diagnosticarCaixas(_ raiz: Entity) {
        let lista = encontrarCaixas(em: raiz)
        print("Caixas encontradas:", lista.count)

        guard let primeira = lista.first else {
            print("Nenhuma entidade começando com P3_Caixa_M. Hierarquia:", raiz.children)
            return
        }

        for aba in abasDe(primeira) {
            let dono = acharPoses(em: aba)
            let juntas = dono?.components[SkeletalPosesComponent.self]?.poses.default?.jointNames
            print("•", aba.name,
                  "→ esqueleto em:", dono?.name ?? "NÃO ENCONTRADO",
                  "| juntas:", juntas ?? [])
        }
    }

    // MARK: - Limpeza do modelo

    private func removerCameras(de entity: Entity) {
        for filho in Array(entity.children) {
            if filho is PerspectiveCamera {
                filho.removeFromParent()
            } else {
                removerCameras(de: filho)
            }
        }
    }
}

func aplicarCores(em entity: Entity) {
    let cores: [String: UIColor] = [
        "Paredes":   .systemGray5,
        "Piso":      .brown,
        "Teto":      .white,
        "Cama":      .systemBlue,
        "Mesa":      .systemOrange,
        "Cabiceira": .systemOrange,
        "Tapete":    .systemRed,
        "Armário":   .systemTeal,
        "Vaso":      .systemGreen
    ]

    if let modelo = entity as? ModelEntity,
       let nomePai = entity.parent?.name,
       let cor = cores[nomePai] {
        modelo.model?.materials = [SimpleMaterial(color: cor, roughness: 0.8, isMetallic: false)]
    }

    for filho in entity.children {
        aplicarCores(em: filho)
    }
}

#Preview {
    moveCamera()
}
