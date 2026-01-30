Shader "Lisii/postProcess/Blur"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _BlurRadius ("Blur Radius", Float) = 1 // Kawase 算法中这个值作为 Offset 乘数
    }

    SubShader
    {
        Cull Off
        ZWrite Off
        ZTest Always

        CGINCLUDE
        #include "UnityCG.cginc"

        sampler2D _MainTex;
        float4 _MainTex_TexelSize;
        int _BlurRadius;

        // 由 C# 传入的模糊方向向量 (1,0) 或 (0,1)，避免 Shader 内部 if 判断
        float2 _BlurOffset;

        struct v2f
        {
            float4 pos : SV_POSITION;
            float2 uv : TEXCOORD0;
        };

        v2f vert(appdata_img v)
        {
            v2f o;
            o.pos = UnityObjectToClipPos(v.vertex);
            o.uv = v.texcoord;
            return o;
        }

        // --- 算法实现区域 ---

        // 1. Box Blur 算法
        fixed4 FragBoxBlur(v2f i) : SV_Target
        {
            fixed4 col = 0;
            // 简单的优化：尽量避免除法在循环内，虽然编译器可能会优化
            float weight = 1.0 / ((_BlurRadius * 2 + 1) * (_BlurRadius * 2 + 1));

            for (int x = -_BlurRadius; x <= _BlurRadius; x++)
            {
                for (int y = -_BlurRadius; y <= _BlurRadius; y++)
                {
                    float2 offset = float2(x, y) * _MainTex_TexelSize.xy;
                    col += tex2D(_MainTex, i.uv + offset);
                }
            }
            return col * weight;
        }

        // 2. Gaussian Blur 算法 (单向，依赖 _BlurOffset)
        fixed4 FragGaussianBlur(v2f i) : SV_Target
        {
            fixed4 col = 0;
            float totalWeight = 0.0;

            // sigma 通常设为 radius / 3.0，或者直接关联
            float sigma = max(_BlurRadius / 3.0, 0.001);
            float twoSigmaSq = 2.0 * sigma * sigma;

            for (int k = -_BlurRadius; k <= _BlurRadius; k++)
            {
                // 计算高斯权重
                float weight = exp(-(k * k) / twoSigmaSq);

                // 利用 _BlurOffset 控制是横向还是纵向 (k * (1,0) 或 k * (0,1))
                float2 offset = _BlurOffset * (k * _MainTex_TexelSize.xy);

                col += tex2D(_MainTex, i.uv + offset) * weight;
                totalWeight += weight;
            }

            return col / totalWeight;
        }

        // 3. Dual Kawase 算法

        // Pass 2: Dual Kawase Downsample
        // 采样 4 个角，每个角偏移 1 个单位（根据 radius 调整）
        fixed4 FragKawaseDown(v2f i) : SV_Target
        {
            float2 halfPixel = _MainTex_TexelSize.xy * (_BlurRadius + 0.5);
            // 0.5 偏移能利用线性采样获得更好效果

            fixed4 sum = tex2D(_MainTex, i.uv + float2(-1, -1) * halfPixel);
            sum += tex2D(_MainTex, i.uv + float2(1, -1) * halfPixel);
            sum += tex2D(_MainTex, i.uv + float2(-1, 1) * halfPixel);
            sum += tex2D(_MainTex, i.uv + float2(1, 1) * halfPixel);

            return sum * 0.25;
        }

        // Pass 3: Dual Kawase Upsample
        // 采样 8 个点来平滑结果
        fixed4 FragKawaseUp(v2f i) : SV_Target
        {
            float2 halfPixel = _MainTex_TexelSize.xy * (_BlurRadius + 0.5);

            fixed4 sum = tex2D(_MainTex, i.uv + float2(-1, -1) * halfPixel);
            sum += tex2D(_MainTex, i.uv + float2(0, -1) * halfPixel) * 2.0;
            sum += tex2D(_MainTex, i.uv + float2(1, -1) * halfPixel);
            sum += tex2D(_MainTex, i.uv + float2(-1, 0) * halfPixel) * 2.0;
            sum += tex2D(_MainTex, i.uv + float2(1, 0) * halfPixel) * 2.0;
            sum += tex2D(_MainTex, i.uv + float2(-1, 1) * halfPixel);
            sum += tex2D(_MainTex, i.uv + float2(0, 1) * halfPixel) * 2.0;
            sum += tex2D(_MainTex, i.uv + float2(1, 1) * halfPixel);

            return sum / 12.0;
        }

        ENDCG

        // Pass 0: Box Blur
        Pass
        {
            Name "BoxBlur"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment FragBoxBlur
            ENDCG
        }

        // Pass 1: Gaussian Blur (Directional)
        // 这个 Pass 可以被调用两次（一次横向，一次纵向）
        Pass
        {
            Name "GaussianBlur"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment FragGaussianBlur
            ENDCG
        }

        // Pass 2: Kawase Down
        Pass
        {
            Name "KawaseDown"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment FragKawaseDown
            ENDCG
        }

        // Pass 3: Kawase Up
        Pass
        {
            Name "KawaseUp"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment FragKawaseUp
            ENDCG
        }
    }
}