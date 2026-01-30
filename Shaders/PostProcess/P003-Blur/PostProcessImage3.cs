using UnityEngine;
using System.Collections.Generic;

[ExecuteInEditMode]
[RequireComponent(typeof(Camera))]
public class PostProcessBlur : MonoBehaviour
{
    public enum BlurMethod
    {
        BoxBlur = 0,
        GaussianBlur = 1,
        DualKawase = 2
    }

    [Header("Settings")]
    public Material postProcessMaterial;
    public BlurMethod blurMethod = BlurMethod.GaussianBlur;

    [Range(0, 10)]
    public int iterations = 4; // 迭代次数，对 Kawase 来说，这是金字塔层数

    [Range(0, 10)]
    public int blurRadius = 1; // 模糊半径/偏移量

    [Range(1, 8)]
    public int downSample = 2; // 降采样倍数

    // Shader Pass 索引常数，对应 Shader 中的顺序
    private const int PASS_BOX = 0;
    private const int PASS_GAUSSIAN = 1;
    private const int PASS_KAWASE_DOWN = 2;
    private const int PASS_KAWASE_UP = 3;

    // 参数 ID 缓存，微小的性能优化
    private static readonly int UniformBlurRadius = Shader.PropertyToID("_BlurRadius");
    private static readonly int UniformBlurOffset = Shader.PropertyToID("_BlurOffset");

    // Kawase 专用：缓存临时的 RT 数组
    struct Level
    {
        public int down;
        public int up;
    }


    void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        if (postProcessMaterial == null)
        {
            Graphics.Blit(src, dest);
            return;
        }

        // 设置通用参数
        postProcessMaterial.SetFloat(UniformBlurRadius, blurRadius);

        // 分支处理
        if (blurMethod == BlurMethod.DualKawase)
        {
            RenderDualKawase(src, dest);
        }
        else
        {
            RenderStandardBlur(src, dest);
        }
    }

    // Dual Kawase 核心逻辑 (金字塔结构) 
    void RenderDualKawase(RenderTexture src, RenderTexture dest)
    {
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
            // 注意：通常 Kawase Up 是叠加，但这里我们直接 Blit 覆盖，
            // 真正的混合是在 Shader 采样时完成的（采样了周围的像素）
            Graphics.Blit(nextRT, currentRT, postProcessMaterial, PASS_KAWASE_UP);
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

    void RenderStandardBlur(RenderTexture src, RenderTexture dest)
    {
        // 1. 初始化
        // 使用降采样可以极大提升性能并增加模糊范围
        int width = src.width / downSample;
        int height = src.height / downSample;

        // 申请两个 Buffer 用于乒乓交替
        RenderTexture rt1 = RenderTexture.GetTemporary(width, height, 0, src.format);
        RenderTexture rt2 = RenderTexture.GetTemporary(width, height, 0, src.format);

        // 确保采样模式为 Bilinear，否则低分辨率下会有锯齿
        rt1.filterMode = FilterMode.Bilinear;
        rt2.filterMode = FilterMode.Bilinear;

        // 2. 将原图拷贝到第一个缓冲区 (Downsample pass)
        Graphics.Blit(src, rt1);

        // 3. 执行模糊迭代
        for (int i = 0; i < iterations; i++)
        {
            switch (blurMethod)
            {
                case BlurMethod.BoxBlur:
                    // Box Blur 只需要一次 Pass，但为了迭代效果，我们在两个 RT 间倒手
                    Graphics.Blit(rt1, rt2, postProcessMaterial, PASS_BOX);
                    Swap(ref rt1, ref rt2);
                    break;

                case BlurMethod.GaussianBlur:
                    // 高斯模糊需要两步：横向 + 纵向

                    // Pass 1: Horizontal -> 结果存入 rt2
                    postProcessMaterial.SetVector(UniformBlurOffset, new Vector2(1, 0));
                    Graphics.Blit(rt1, rt2, postProcessMaterial, PASS_GAUSSIAN);

                    // Pass 2: Vertical (从 rt2 读) -> 结果存回 rt1
                    postProcessMaterial.SetVector(UniformBlurOffset, new Vector2(0, 1));
                    Graphics.Blit(rt2, rt1, postProcessMaterial, PASS_GAUSSIAN);

                    // 注意：这里不需要 Swap，因为经过两步后，结果已经回到了 rt1
                    break;
            }
        }

        // 4. 将最终结果 (rt1) 输出到屏幕 (Upsample pass)
        Graphics.Blit(rt1, dest);

        // 5. 释放临时内存
        RenderTexture.ReleaseTemporary(rt1);
        RenderTexture.ReleaseTemporary(rt2);
    }

    // 辅助函数：交换引用
    private void Swap(ref RenderTexture a, ref RenderTexture b)
    {
        RenderTexture temp = a;
        a = b;
        b = temp;
    }
}