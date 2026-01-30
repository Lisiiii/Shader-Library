Shader "Lisii/postProcess/Bloom"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _BloomIntensity ("Bloom Intensity", Float) = 1.0
        _Threshold ("Threshold", Range(0, 2)) = 0.5
        _BlurRadius ("Blur Radius", Float) = 1 // Kawase 算法中这个值作为 Offset 乘数
        _BlurTargetTex ("Blur Target Texture", 2D) = "white" {} // 用于混合的模糊结果纹理
    }
    SubShader
    {
        // No culling or depth
        Cull Off
        ZWrite Off
        ZTest Always

        CGINCLUDE
        #include "UnityCG.cginc"

        sampler2D _MainTex;
        sampler2D _BlurTargetTex;
        float _BloomIntensity;
        float _Threshold;
        float4 _MainTex_TexelSize;
        int _BlurRadius;

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

        fixed4 frag_prefilter(v2f i) : SV_Target
        {
            fixed4 col = tex2D(_MainTex, i.uv);
            // 提取高亮部分
            float brightest = max(max(col.r, col.g), col.b);
            brightest = max(brightest - _Threshold, 0.0) / (brightest + 0.000001);
            col.rgb *= brightest;

            return col;
        }

        // Dual Kawase 算法

        // Dual Kawase Downsample
        // 采样 4 个角，每个角偏移 1 个单位（根据 radius 调整）
        fixed4 frag_kawase_down(v2f i) : SV_Target
        {
            float2 halfPixel = _MainTex_TexelSize.xy * (_BlurRadius + 0.5);
            // 0.5 偏移能利用线性采样获得更好效果

            fixed4 sum = tex2D(_MainTex, i.uv + float2(-1, -1) * halfPixel);
            sum += tex2D(_MainTex, i.uv + float2(1, -1) * halfPixel);
            sum += tex2D(_MainTex, i.uv + float2(-1, 1) * halfPixel);
            sum += tex2D(_MainTex, i.uv + float2(1, 1) * halfPixel);

            return sum * 0.25;
        }

        // Dual Kawase Upsample
        // 采样 8 个点来平滑结果
        fixed4 frag_kawase_up(v2f i) : SV_Target
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

            sum /= 12.0;
            // 叠加原图以实现 Bloom 效果
            fixed4 original = tex2D(_BlurTargetTex, i.uv);
            sum += original;

            return sum;
        }

        fixed4 frag_add(v2f i) : SV_Target
        {
            fixed4 col1 = tex2D(_MainTex, i.uv);
            fixed4 col2 = tex2D(_BlurTargetTex, i.uv);
            return col1 + col2 * _BloomIntensity;
        }


        ENDCG
        Pass
        {
            name "Prefilter"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag_prefilter
            ENDCG
        }
        Pass
        {
            Name "KawaseDown"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag_kawase_down
            ENDCG
        }
        Pass
        {
            Name "KawaseUp"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag_kawase_up
            ENDCG
        }
        Pass
        {
            Name "BlendBloom"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag_add
            ENDCG
        }
    }
}