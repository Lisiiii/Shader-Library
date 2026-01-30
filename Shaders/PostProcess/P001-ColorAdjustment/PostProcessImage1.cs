using UnityEngine;

[ExecuteInEditMode]
public class PostProcessImage1 : MonoBehaviour
{
    public Material postProcessMaterial;
    [Range(0, 2)]
    public float brightness = 1f;
    [Range(0, 2)]
    public float saturation = 1f;
    [Range(0, 2)]
    public float contrast = 1f;
    [Range(0, 2)]
    public float vignetteIntensity = 0.7f;
    [Range(0, 1)]
    public float vignetteRoughness = 0.5f;
    [Range(0, 2)]
    public float vignetteSmoothness = 1f;
    [Range(0, 1)]
    public float hueShift = 0f;

    // Start is called once before the first execution of Update after the MonoBehaviour is created
    void Start()
    {

    }

    // Update is called once per frame
    void Update()
    {

    }

    void OnRenderImage(RenderTexture src, RenderTexture dest)
    {
        postProcessMaterial.SetFloat("_Brightness", brightness);
        postProcessMaterial.SetFloat("_Saturation", saturation);
        postProcessMaterial.SetFloat("_Contrast", contrast);
        postProcessMaterial.SetFloat("_VignetteIntensity", vignetteIntensity);
        postProcessMaterial.SetFloat("_VignetteRoughness", vignetteRoughness);
        postProcessMaterial.SetFloat("_VignetteSmoothness", vignetteSmoothness);
        postProcessMaterial.SetFloat("_HueShift", hueShift);

        Graphics.Blit(src, dest, postProcessMaterial);

    }
}
