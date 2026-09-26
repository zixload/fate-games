#include "CodexAnimGraphLibrary.h"

#include "Animation/AnimBlueprint.h"
#include "AnimGraphNode_Root.h"
#include "AnimGraphNode_Slot.h"
#include "AnimGraphNode_ModifyBone.h"
#include "AnimGraphNode_LocalToComponentSpace.h"
#include "AnimGraphNode_ComponentToLocalSpace.h"
#include "EdGraph/EdGraph.h"
#include "EdGraph/EdGraphPin.h"
#include "EdGraph/EdGraphSchema.h"
#include "EdGraphSchema_K2.h"
#include "K2Node_VariableGet.h"
#include "Kismet2/BlueprintEditorUtils.h"

bool UCodexAnimGraphLibrary::EnsureDefaultSlot(UAnimBlueprint* Blueprint)
{
    if (!Blueprint) return false;

    TArray<UEdGraph*> Graphs;
    Blueprint->GetAllGraphs(Graphs);
    UEdGraph* Graph = nullptr;
    for (UEdGraph* Candidate : Graphs)
    {
        if (Candidate && Candidate->GetFName() == FName(TEXT("AnimGraph")))
        {
            Graph = Candidate;
            break;
        }
    }
    if (!Graph) return false;

    UAnimGraphNode_Root* Root = nullptr;
    for (UEdGraphNode* Existing : Graph->Nodes)
    {
        if (Cast<UAnimGraphNode_Slot>(Existing)) return true;
        if (UAnimGraphNode_Root* Candidate = Cast<UAnimGraphNode_Root>(Existing)) Root = Candidate;
    }
    if (!Root) return false;

    UEdGraphPin* RootInput = nullptr;
    for (UEdGraphPin* Pin : Root->Pins)
    {
        if (Pin && Pin->Direction == EGPD_Input && Pin->LinkedTo.Num() == 1)
        {
            RootInput = Pin;
            break;
        }
    }
    if (!RootInput) return false;
    UEdGraphPin* PreviousOutput = RootInput->LinkedTo[0];

    Blueprint->Modify();
    Graph->Modify();
    Root->Modify();
    FGraphNodeCreator<UAnimGraphNode_Slot> Creator(*Graph);
    UAnimGraphNode_Slot* Slot = Creator.CreateNode();
    Slot->Node.SlotName = FName(TEXT("DefaultSlot"));
    Slot->NodePosX = Root->NodePosX - 250;
    Slot->NodePosY = Root->NodePosY;
    Creator.Finalize();

    UEdGraphPin* SlotInput = nullptr;
    UEdGraphPin* SlotOutput = nullptr;
    for (UEdGraphPin* Pin : Slot->Pins)
    {
        if (Pin && Pin->Direction == EGPD_Input && !SlotInput) SlotInput = Pin;
        if (Pin && Pin->Direction == EGPD_Output && !SlotOutput) SlotOutput = Pin;
    }
    if (!SlotInput || !SlotOutput) return false;

    RootInput->BreakAllPinLinks();
    const UEdGraphSchema* Schema = Graph->GetSchema();
    if (!Schema->TryCreateConnection(PreviousOutput, SlotInput) ||
        !Schema->TryCreateConnection(SlotOutput, RootInput)) return false;

    FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Blueprint);
    return true;
}

namespace
{
UEdGraphPin* FindPin(UEdGraphNode* Node, EEdGraphPinDirection Direction, const TCHAR* Name)
{
    for (UEdGraphPin* Pin : Node->Pins)
    {
        if (Pin && Pin->Direction == Direction && Pin->PinName == FName(Name)) return Pin;
    }
    FString Available;
    for (UEdGraphPin* Pin : Node->Pins)
    {
        if (Pin) Available += FString::Printf(TEXT(" %s(%d)"), *Pin->PinName.ToString(), int32(Pin->Direction));
    }
    UE_LOG(LogTemp, Warning, TEXT("CodexLook missing %s on %s; pins:%s"), Name,
        *Node->GetClass()->GetName(), *Available);
    return nullptr;
}

template <typename T>
T* AddNode(UEdGraph* Graph, int32 X, int32 Y)
{
    FGraphNodeCreator<T> Creator(*Graph);
    T* Node = Creator.CreateNode();
    Node->NodePosX = X;
    Node->NodePosY = Y;
    Creator.Finalize();
    return Node;
}
}

bool UCodexAnimGraphLibrary::EnsureSeatedLook(UAnimBlueprint* Blueprint)
{
    if (!Blueprint) return false;
    UEdGraph* Graph = nullptr;
    TArray<UEdGraph*> Graphs;
    Blueprint->GetAllGraphs(Graphs);
    for (UEdGraph* Candidate : Graphs)
    {
        if (Candidate && Candidate->GetFName() == FName(TEXT("AnimGraph"))) Graph = Candidate;
    }
    if (!Graph) return false;

    UAnimGraphNode_Root* Root = nullptr;
    for (UEdGraphNode* Existing : Graph->Nodes)
    {
        if (UAnimGraphNode_ModifyBone* Modify = Cast<UAnimGraphNode_ModifyBone>(Existing))
        {
            if (Modify->Node.BoneToModify.BoneName == FName(TEXT("Head"))) return true;
        }
        if (UAnimGraphNode_Root* Candidate = Cast<UAnimGraphNode_Root>(Existing)) Root = Candidate;
    }
    if (!Root) return false;
    UEdGraphPin* RootInput = FindPin(Root, EGPD_Input, TEXT("Result"));
    if (!RootInput || RootInput->LinkedTo.Num() != 1)
    {
        UE_LOG(LogTemp, Warning, TEXT("CodexLook root input missing or link count invalid"));
        return false;
    }
    UEdGraphPin* PreviousOutput = RootInput->LinkedTo[0];

    FEdGraphPinType RotationType;
    RotationType.PinCategory = UEdGraphSchema_K2::PC_Struct;
    RotationType.PinSubCategoryObject = TBaseStructure<FRotator>::Get();
    for (const TCHAR* VarName : { TEXT("LookNeck"), TEXT("LookHead") })
    {
        if (FBlueprintEditorUtils::FindNewVariableIndex(Blueprint, FName(VarName)) == INDEX_NONE &&
            !FBlueprintEditorUtils::AddMemberVariable(Blueprint, FName(VarName), RotationType))
        {
            UE_LOG(LogTemp, Warning, TEXT("CodexLook cannot add variable %s"), VarName);
            return false;
        }
    }

    Blueprint->Modify();
    Graph->Modify();
    Root->Modify();

    auto* ToComponent = AddNode<UAnimGraphNode_LocalToComponentSpace>(Graph, Root->NodePosX - 900, Root->NodePosY);
    auto* Neck = AddNode<UAnimGraphNode_ModifyBone>(Graph, Root->NodePosX - 700, Root->NodePosY);
    auto* Head = AddNode<UAnimGraphNode_ModifyBone>(Graph, Root->NodePosX - 450, Root->NodePosY);
    auto* ToLocal = AddNode<UAnimGraphNode_ComponentToLocalSpace>(Graph, Root->NodePosX - 200, Root->NodePosY);

    Neck->Node.BoneToModify.BoneName = FName(TEXT("Neck"));
    Head->Node.BoneToModify.BoneName = FName(TEXT("Head"));
    for (UAnimGraphNode_ModifyBone* Modify : { Neck, Head })
    {
        Modify->Node.TranslationMode = BMM_Ignore;
        Modify->Node.RotationMode = BMM_Additive;
        Modify->Node.ScaleMode = BMM_Ignore;
        Modify->Node.RotationSpace = BCS_BoneSpace;
    }

    auto AddRotationVariable = [&](const TCHAR* Name, UAnimGraphNode_ModifyBone* Modify, int32 X, int32 Y) -> bool
    {
        FGraphNodeCreator<UK2Node_VariableGet> Creator(*Graph);
        UK2Node_VariableGet* Getter = Creator.CreateNode();
        Getter->VariableReference.SetSelfMember(FName(Name));
        Getter->NodePosX = X;
        Getter->NodePosY = Y;
        Creator.Finalize();
        UEdGraphPin* Value = FindPin(Getter, EGPD_Output, Name);
        UEdGraphPin* Rotation = FindPin(Modify, EGPD_Input, TEXT("Rotation"));
        return Value && Rotation && Graph->GetSchema()->TryCreateConnection(Value, Rotation);
    };

    const UEdGraphSchema* Schema = Graph->GetSchema();
    UEdGraphPin* InLocal = FindPin(ToComponent, EGPD_Input, TEXT("LocalPose"));
    UEdGraphPin* OutComponent = FindPin(ToComponent, EGPD_Output, TEXT("ComponentPose"));
    UEdGraphPin* NeckInput = FindPin(Neck, EGPD_Input, TEXT("ComponentPose"));
    UEdGraphPin* NeckOutput = FindPin(Neck, EGPD_Output, TEXT("Pose"));
    UEdGraphPin* HeadInput = FindPin(Head, EGPD_Input, TEXT("ComponentPose"));
    UEdGraphPin* HeadOutput = FindPin(Head, EGPD_Output, TEXT("Pose"));
    UEdGraphPin* InComponent = FindPin(ToLocal, EGPD_Input, TEXT("ComponentPose"));
    UEdGraphPin* OutLocal = FindPin(ToLocal, EGPD_Output, TEXT("Pose"));
    if (!InLocal || !OutComponent || !NeckInput || !NeckOutput || !HeadInput || !HeadOutput ||
        !InComponent || !OutLocal) return false;

    RootInput->BreakAllPinLinks();
    if (!Schema->TryCreateConnection(PreviousOutput, InLocal) ||
        !Schema->TryCreateConnection(OutComponent, NeckInput) ||
        !Schema->TryCreateConnection(NeckOutput, HeadInput) ||
        !Schema->TryCreateConnection(HeadOutput, InComponent) ||
        !Schema->TryCreateConnection(OutLocal, RootInput) ||
        !AddRotationVariable(TEXT("LookNeck"), Neck, Neck->NodePosX, Neck->NodePosY + 240) ||
        !AddRotationVariable(TEXT("LookHead"), Head, Head->NodePosX, Head->NodePosY + 240))
    {
        UE_LOG(LogTemp, Warning, TEXT("CodexLook pose or rotation connection failed"));
        return false;
    }

    FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Blueprint);
    return true;
}
