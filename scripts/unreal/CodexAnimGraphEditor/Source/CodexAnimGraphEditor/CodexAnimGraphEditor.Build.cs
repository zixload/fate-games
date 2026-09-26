using UnrealBuildTool;

public class CodexAnimGraphEditor : ModuleRules
{
    public CodexAnimGraphEditor(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new[] { "Core", "CoreUObject", "Engine" });
        PrivateDependencyModuleNames.AddRange(new[] { "AnimGraph", "AnimGraphRuntime", "BlueprintGraph", "UnrealEd" });
    }
}
