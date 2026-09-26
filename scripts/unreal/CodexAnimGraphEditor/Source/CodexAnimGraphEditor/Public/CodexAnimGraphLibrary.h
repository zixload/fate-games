#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "CodexAnimGraphLibrary.generated.h"

class UAnimBlueprint;

UCLASS()
class CODEXANIMGRAPHEDITOR_API UCodexAnimGraphLibrary : public UBlueprintFunctionLibrary
{
    GENERATED_BODY()

public:
    UFUNCTION(BlueprintCallable, Category = "Codex|Animation")
    static bool EnsureDefaultSlot(UAnimBlueprint* Blueprint);

    UFUNCTION(BlueprintCallable, Category = "Codex|Animation")
    static bool EnsureSeatedLook(UAnimBlueprint* Blueprint);
};
