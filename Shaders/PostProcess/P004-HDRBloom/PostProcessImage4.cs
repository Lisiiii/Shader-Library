using Unity.VisualScripting;
using UnityEngine;

[ExecuteInEditMode]
public class PostProcessImage4 : MonoBehaviour
{
    public Material postProcessMaterial;
    [Header("Bloom Settings")]
    [Range(0.0f, 2.0f)]
    public float threshold = 0.5f;
    public float bloomIntensity = 1.0f;
    [Header("Kawase Blur Settings")]
    [Range(0, 10)]
    public int iterations = 4; // 金字塔层数
    [Range(1, 8)]
    public int downSample = 2; // 降采样倍数
    [Range(0, 10)]
    public int blurRadius = 1; // 模糊半径/偏移量

    // Shader Pass 索引常数，对应 Shader 中的顺序
    private const int PASS_PRE_FILTER = 0;
    private const int PASS_KAWASE_DOWN = 1;
    private const int PASS_KAWASE_UP = 2;
    private const int PASS_BLEND = 3;

    // 参数 ID 缓存，微小的性能优化
    private static readonly int UniformBloomIntensity = Shader.PropertyToID("_BloomIntensity");
    private static readonly int UniformThreshold = Shader.PropertyToID("_Threshold");
    private static readonly int UniformBlurRadius = Shader.PropertyToID("_BlurRadius");
    private static readonly int UniformBlurTargetTex = Shader.PropertyToID("_BlurTargetTex");

    struct Level
    {
        public int down;
        public int up;
    }

    void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        int width = src.width;
        int height = src.height;
        // 1. 预过滤，提取高亮部分
        RenderTexture preFiltered = RenderTexture.GetTemporary(width, height, 0, src.format);
        PreFilter(src, preFiltered);
        // 2. Dual Kawase 模糊
        RenderTexture blurred = RenderTexture.GetTemporary(width, height, 0, src.format);
        RenderDualKawase(preFiltered, blurred);

        // 3. 合成
        BlendBloom(src, blurred, dest);

        // Debug
        // Graphics.Blit(preFiltered, dest);

        // 释放临时 RT
        RenderTexture.ReleaseTemporary(preFiltered);
        RenderTexture.ReleaseTemporary(blurred);
    }
    void PreFilter(RenderTexture src, RenderTexture dest)
    {
        postProcessMaterial.SetFloat(UniformThreshold, threshold);
        Graphics.Blit(src, dest, postProcessMaterial, PASS_PRE_FILTER);
    }
    // Dual Kawase 核心逻辑 (金字塔结构) 
    void RenderDualKawase(RenderTexture src, RenderTexture dest)
    {
        postProcessMaterial.SetInt(UniformBlurRadius, blurRadius);
        // 1. 初始化
        int width = src.width / downSample;
        int height = src.height / downSample;

        // 这里的 iterations 代表金字塔的层数
        // 我们需要一个数组存下每一层的 RenderTexture
        RenderTexture[] pyramid = new RenderTexture[iterations];

        // 2. Downsample Loop (降采样阶段)
        RenderTexture lastRT = src;

        for (int i = 0; i < iterations; i++)
        {
            // 每次迭代分辨率减半
            // 注意：太小的分辨率(如 1x1)会导致渲染问题，加个 Mathf.Max 保护
            int w = Mathf.Max(1, width >> i); // 位运算右移等同于除以2
            int h = Mathf.Max(1, height >> i);

            pyramid[i] = RenderTexture.GetTemporary(w, h, 0, src.format);
            pyramid[i].filterMode = FilterMode.Bilinear;

            // 调用 Pass 2: Kawase Down
            Graphics.Blit(lastRT, pyramid[i], postProcessMaterial, PASS_KAWASE_DOWN);

            lastRT = pyramid[i];
        }

        // 3. Upsample Loop (升采样阶段)
        // 从最小的图开始往回叠
        for (int i = iterations - 2; i >= 0; i--)
        {
            RenderTexture currentRT = pyramid[i]; // 这一层是目标
            RenderTexture nextRT = pyramid[i + 1]; // 这一层是源 (更小的图)

            // 调用 Pass 3: Kawase Up
            // 将更小的图(nextRT) 混合回 较大的图(currentRT)
            // 注意：Bloom 效果需要累加混合,这一步在Shader中处理,需要将目标RT传入
            RenderTexture bufferRT = RenderTexture.GetTemporary(currentRT.width, currentRT.height, 0, currentRT.format);
            Graphics.Blit(currentRT, bufferRT);
            postProcessMaterial.SetTexture(UniformBlurTargetTex, bufferRT);
            Graphics.Blit(nextRT, currentRT, postProcessMaterial, PASS_KAWASE_UP);

            // 释放临时 RT
            RenderTexture.ReleaseTemporary(bufferRT);
        }

        // 4. 输出最终结果
        // pyramid[0] 现在包含了经过一轮 "下潜" 和 "上浮" 后的结果
        Graphics.Blit(pyramid[0], dest);

        // 5. 清理内存
        for (int i = 0; i < iterations; i++)
        {
            RenderTexture.ReleaseTemporary(pyramid[i]);
        }
    }

    void BlendBloom(RenderTexture src, RenderTexture bloom, RenderTexture dest)
    {
        postProcessMaterial.SetTexture(UniformBlurTargetTex, bloom);
        postProcessMaterial.SetFloat(UniformBloomIntensity, bloomIntensity);
        Graphics.Blit(src, dest, postProcessMaterial, PASS_BLEND);
    }
}
