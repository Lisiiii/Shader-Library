// ================================================
// Post-Processing Shader: Color Adjustment & Vignette
// ================================================
Shader "Lisii/postProcess/ColorAdjustment"
{
    Properties
    {
        // 主纹理 - 输入的后处理源纹理，由相机渲染得到
        _MainTex ("Texture", 2D) = "white" {}

        // 亮度控制 - 控制图像整体明暗度
        // 范围：0（全黑）~ 2（两倍亮度）
        _Brightness ("Brightness", Range(0, 2)) = 1

        // 饱和度控制 - 控制色彩鲜艳程度
        // 范围：0（完全灰度）~ 2（超饱和）
        _Saturation ("Saturation", Range(0, 2)) = 1

        // 对比度控制 - 控制明暗区域差异程度
        // 范围：0（完全灰色）~ 2（高对比）
        _Contrast ("Contrast", Range(0, 2)) = 1

        // 暗角强度 - 控制图像边缘变暗的程度
        // 范围：0（无暗角）~ 2（强暗角）
        _VignetteIntensity ("Vignette Intensity", Range(0, 2)) = 0.7

        // 暗角粗糙度 - 控制暗角从中心开始的扩散距离
        // 值越小暗角越靠边缘，值越大暗角越靠近中心
        _VignetteRoughness ("Vignette Roughness", Range(0, 1)) = 0.5

        // 暗角平滑度 - 控制暗角边缘的过渡平滑程度
        // 值越小边缘越锐利，值越大过渡越平滑
        _VignetteSmoothness ("Vignette Smoothness", Range(0, 2)) = 1

        // 色相偏移 - 控制整体色相旋转
        // 范围：0~1（对应0°~360°色相环）
        _HueShift ("Hue Shift", Range(0, 1)) = 0
    }

    SubShader
    {
        // 后处理设置：
        // Cull Off      - 禁用面片剔除（正反面都渲染）
        // ZWrite Off    - 不写入深度缓冲区
        // ZTest Always  - 总是通过深度测试（保证全屏绘制）
        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _MainTex;
            float _Brightness;
            float _Saturation;
            float _Contrast;
            float _VignetteIntensity;
            float _VignetteRoughness;
            float _VignetteSmoothness;
            float _HueShift;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            float3 HSV2RGB(float3 c)
            {
                float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
                float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
                return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
            }

            float3 RGB2HSV(float3 c)
            {
                float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
                float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
                float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

                float d = q.x - min(q.w, q.y);
                float e = 1.0e-10;
                return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
            }


            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }


            half4 frag(v2f i) : SV_Target
            {
                // 步骤1：从主纹理采样原始颜色
                // 采样当前像素对应的纹理颜色（RGBA格式）
                half4 col = tex2D(_MainTex, i.uv);

                // - 亮度调整
                // 将RGB各通道乘以亮度系数，线性改变整体亮度
                half3 final_color = col.rgb * _Brightness;

                // - 色相调整
                // 将RGB颜色转换为HSV空间，调整色相后再转换回RGB
                float3 hsv = RGB2HSV(final_color);
                // 提取色相分量
                hsv.r += _HueShift;
                final_color = HSV2RGB(hsv);

                // - 饱和度调整
                // 计算当前颜色亮度，在灰度值和原始颜色之间插值
                // 1. 计算亮度（伽马空间下的亮度公式）
                // 伽马空间下公式1：float lumin = dot(brightness_adjusted_color, float3(0.22, 0.707, 0.071));
                // 线性空间下公式2：float lumin = dot(brightness_adjusted_color, float3(0.0396,0.458,0,0061));
                float lumin = dot(final_color, float3(0.22, 0.707, 0.071));
                // 2.插值
                final_color = lerp(lumin.xxx, final_color, _Saturation);
                // 2. 根据饱和度参数在灰度和彩色之间插值
                // 当_Saturation=0时：完全灰度
                // 当_Saturation=1时：原始颜色
                // 当_Saturation>1时：超饱和（增强颜色差异）
                final_color = lerp(lumin.xxx, final_color, _Saturation);

                // - 对比度调整
                // 以中性灰(0.5,0.5,0.5)为基准进行插值
                // 定义中性灰色（对比度调整的基准点）
                float3 mid_color = float3(0.5, 0.5, 0.5);
                // 插值计算：对比度越高，颜色越偏离中性灰
                final_color = lerp(mid_color, final_color, _Contrast);

                // - 暗角效果（Vignette）
                // 基于到图像中心的距离，边缘应用透明度衰减
                // 1. 将UV从[0,1]范围转换到[-1,1]范围
                //    使坐标原点位于图像中心
                float2 uv = i.uv * 2.0 - 1.0;

                // 2. 计算当前像素到图像中心的距离（欧几里得距离）
                //    length()函数计算向量长度
                float dist = length(uv);

                // 3. 使用smoothstep创建平滑的暗角遮罩
                //    smoothstep产生一个在指定范围内平滑过渡的值
                //    参数解释：
                //    - 1.0 - _VignetteRoughness：暗角开始的位置
                //    - 1.0 - _VignetteRoughness + _VignetteSmoothness：暗角结束的位置
                //    - dist：当前像素到中心的距离
                float vignette = smoothstep(1.0 - _VignetteRoughness, 1.0 - _VignetteRoughness + _VignetteSmoothness, dist);

                // 4. 应用暗角效果到最终颜色
                //    lerp在1.0和(1.0 - 暗角强度)之间插值
                //    vignette值越大（越靠边缘），颜色越暗
                final_color *= lerp(1.0, 1.0 - _VignetteIntensity, vignette);

                return half4(final_color, col.a);
            }


            ENDCG
        }
    }
}