---
title: Neurocritical Care Overview
category: synthesis
tags:
  - ncx
  - neurocritical-care
  - synthesis
  - guidelines
aliases:
  - neurocritical care
  - cuidados neurocríticos
sources:
  - "Greenberg - Handbook of Neurosurgery (10ed, 2023)"
summary: >-
  Master overview of neurocritical care: ICP management, coma assessment, brain death, herniation recognition, and pharmacology.
provenance:
  extracted: 0.80
  inferred: 0.15
  ambiguous: 0.05
created: 2026-04-15
updated: 2026-04-15
---

# Neurocritical Care Overview

Integration of core neurocritical care topics from the NCX library. This page serves as a decision tree and cross-reference map for the neuro-ICU.

## Core Decision Pathway

```
Patient arrives with altered consciousness
    │
    ├─ Stabilize (ABC) → Labs → Emergency meds
    │   (see [[coma-assessment]])
    │
    ├─ Assess [[glasgow-coma-scale|GCS]]
    │   ├─ GCS ≤ 8 → Intubate → CT
    │   ├─ GCS 9-12 → Close monitoring → CT
    │   └─ GCS 13-15 → Focused workup
    │
    ├─ Identify cause
    │   ├─ Structural → [[herniation-syndromes|Herniation]]?
    │   │   ├─ Yes → [[intracranial-pressure|ICP management]] → Surgery
    │   │   └─ No → Targeted treatment
    │   └─ Metabolic → Correct underlying cause
    │
    └─ If progression to brain death
        → [[brain-death]] protocol
```

## Domain Map

| Domain | Key Pages | Primary Greenberg Chapters |
|--------|-----------|---------------------------|
| Consciousness | [[glasgow-coma-scale]], [[coma-assessment]] | Ch 18 |
| Herniation | [[herniation-syndromes]] | Ch 18.4 |
| ICP | [[intracranial-pressure]] | Ch 65 (TBI section) |
| Brain death | [[brain-death]] | Ch 19 |
| Hydrocephalus | [[hydrocephalus]] | Ch 24-25 |
| Seizures | [[status-epilepticus]] | Ch 28.6 |
| Sodium disorders | [[sodium-homeostasis]] | Ch 5 |

## Critical Thresholds

| Parameter | Target | Action if breached |
|-----------|--------|-------------------|
| ICP | <22 mmHg | Tiered ICP management |
| CPP | 60-70 mmHg | Vasopressors or ICP reduction |
| GCS | ≤8 | Intubate, CT, consider ICP monitor |
| Midline shift | >5 mm with symptoms | Surgical evaluation |
| PaCO2 | 35-40 mmHg | Avoid hypo/hyperventilation |
| Na+ | 135-145 mEq/L | Correct slowly (≤10 mEq/24h) |
| Temperature | <38°C | Aggressive fever management |
| Glucose | 140-180 mg/dL | Insulin protocol |

## Pharmacology Quick Reference

### Osmotherapy
| Agent | Dose | Max osmolality | Notes |
|-------|------|---------------|-------|
| Mannitol 20% | 0.25-1 g/kg IV bolus | Serum <320 mOsm/L | Monitor renal function |
| HTS 23.4% | 30 mL via central line | Serum Na <160 | Rapid onset |
| HTS 3% | 250-500 mL bolus or infusion | Serum Na <160 | Can run peripherally |

### Sedation
| Agent | Indication | Key concern |
|-------|-----------|-------------|
| Propofol | Short-term sedation, ICP control | Propofol infusion syndrome (>48h, >5 mg/kg/hr) |
| Midazolam | Alternative sedation | Longer context-sensitive half-time |
| Pentobarbital | Refractory ICP | Hypotension, immune suppression |
| Fentanyl | Analgesia | Less ICP effect than morphine |

### Anticoagulation Reversal
Critical in neurosurgical emergencies:
| Agent | Reversal | Notes |
|-------|---------|-------|
| Warfarin | IV vitamin K + PCC (4-factor) | FFP if PCC unavailable |
| DOACs (rivaroxaban, apixaban) | Andexanet alfa or PCC | Idarucizumab for dabigatran |
| Heparin | Protamine 1 mg per 100U heparin | Max 50 mg |
| Antiplatelet (aspirin, clopidogrel) | Platelet transfusion (controversial) | DDAVP 0.3 mcg/kg may help |

## Cross-References to Other Subspecialties

- **Cerebrovascular:** [[cerebrovascular-aneurysms-overview]] — SAH management overlaps heavily with neurocritical care (vasospasm, hydrocephalus, rebleeding)
- **Neurotrauma:** TBI management is core neurocritical care (GCS, ICP, CPP)
- **Neuro-oncology:** perioperative care of brain tumor patients (steroids, seizure prophylaxis, venous thromboembolism)

## Related Pages

- [[coma-assessment]] — systematic approach to altered consciousness
- [[glasgow-coma-scale]] — consciousness grading
- [[herniation-syndromes]] — emergency recognition
- [[intracranial-pressure]] — ICP monitoring and management
- [[brain-death]] — determination protocol
- [[hydrocephalus]] — acute and chronic management
