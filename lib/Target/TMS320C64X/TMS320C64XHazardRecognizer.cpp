//===-- TMS320C64XHazardRecognizer.cpp --------------------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file was developed by Alexander Jordan, Vienna University of Technology,
// and is distributed under the University of Illinois Open Source License.
// See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// Implements the hazard recognizer for the TMS320C64X.
//
//===----------------------------------------------------------------------===//

#define DEBUG_TYPE "post-RA-sched"
#define DBGMI(MI) dbgs() << MI->getDesc().getName() << ": "

#include "TMS320C64X.h"
#include "TMS320C64XHazardRecognizer.h"
#include "TMS320C64XInstrInfo.h"
#include "TMS320C64XRegisterInfo.h"

#include "llvm/CodeGen/ScheduleDAG.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
#include <set>

using namespace llvm;

// using namespace TMS320C64X;

namespace llvm {

namespace TMS320C64X {
  class MachineHazards {

    static const int UNITS = 4;
    static const int SIDES = 2;
    std::set<unsigned> Active[SIDES];
    int ExtraActive[NumExtra];
    int MovesOnSide[SIDES];

  public:
    void reset() {
      for (int i = 0; i < SIDES; ++i)
        Active[i].clear();
      for (int i = 0; i < NumExtra; ++i)
        ExtraActive[i] = 0;
      for (int i = 0; i < SIDES; ++i)
        MovesOnSide[i] = 0;
    }
    bool isUnitBusy(unsigned unit) {
      assert(unit < UNITS * SIDES);
      unsigned side = unit & 0x1;
      if (Active[side].count(unit))
        return true;
      if (isLSD(unit >> 1) && moveUnitsAvailable(side) < 1)
        return true;
      return false;
    }
    bool isXResBusy(unsigned xres) {
      return ExtraActive[xres];
    }
    static bool isLSD(unsigned unit) {
      switch (unit >> 1) {
        case TMS320C64XII::unit_l:
        case TMS320C64XII::unit_s:
        case TMS320C64XII::unit_d:
          return true;
      }
      return false;
    }
    unsigned moveUnitsAvailable(unsigned side) {
      assert(side < (unsigned) SIDES);
      // return number of available units not counting .M
      return UNITS - 1 /* .M unit */ - MovesOnSide[side]
        - count_if(Active[side].begin(), Active[side].end(), isLSD);
    }
    void book(unsigned unit, unsigned xres) {
      assert(unit < UNITS * SIDES);
      unsigned side = unit & 0x1;
      Active[side].insert(unit);

      if (xres != None)
        ExtraActive[xres] = 1;
    }
    void bookMove(unsigned side, unsigned xres) {
      assert(side < (unsigned) SIDES);
      MovesOnSide[side]++;

      if (xres != None)
        ExtraActive[xres] = 1;
    }
  };
}

}

//-----------------------------------------------------------------------------

TMS320C64XHazardRecognizer::TMS320C64XHazardRecognizer(const TargetInstrInfo &tii)
: TII(tii),
  Hzd(new TMS320C64X::MachineHazards())
{
  Hzd->reset();
}

//-----------------------------------------------------------------------------

TMS320C64XHazardRecognizer::~TMS320C64XHazardRecognizer() { delete Hzd; }

//-----------------------------------------------------------------------------

void TMS320C64XHazardRecognizer::Reset() { Hzd->reset(); }

//-----------------------------------------------------------------------------

ScheduleHazardRecognizer::HazardType
TMS320C64XHazardRecognizer::getHazardType(SUnit *SU, int stalls) {

  if (isPseudo(SU))
    return NoHazard;

  // schedule moves regardless of resources
  if (isMove(SU))
    return getMoveHazard(SU);

  fixResources(SU);

  unsigned idx = getUnitIndex(SU);
  if (Hzd->isUnitBusy(idx)) {
    static std::string ustr[] = {"L1", "L2", "S1", "S2", "M1", "M2", "D1", "D2"};
    DEBUG(dbgs() << ustr[idx] << " conflict\n");
    return NoopHazard;
  }

  unsigned xuse = getExtraUse(SU);
  if (Hzd->isXResBusy(xuse)) {
    static std::string estr[] = {"error", "T1", "T2", "X1", "X2"};
    DEBUG(dbgs() << estr[xuse] << " conflict\n");
    return NoopHazard;
  }

  DEBUG(dbgs() << "--no hazard\n");
  return NoHazard;
}

//-----------------------------------------------------------------------------

void TMS320C64XHazardRecognizer::EmitInstruction(SUnit *SU) {

  DEBUG(dbgs() << "--emit\n");
  if (isPseudo(SU))
    return;

  // schedule moves flexibily
  if (emitMove(SU))
    return;

  Hzd->book(getUnitIndex(SU), getExtraUse(SU));
}

//-----------------------------------------------------------------------------

void TMS320C64XHazardRecognizer::AdvanceCycle() {

  DEBUG(dbgs() << "--advance\n");
  Hzd->reset();
}

//-----------------------------------------------------------------------------

void TMS320C64XHazardRecognizer::EmitNoop() {
  AdvanceCycle();
}

//-----------------------------------------------------------------------------

unsigned TMS320C64XHazardRecognizer::getUnitIndex(unsigned side, unsigned unit)
{
  assert(side < 2 && unit < 4);
  unsigned idx = unit << 1;
  idx |= side;
  return idx;
}

//-----------------------------------------------------------------------------

unsigned TMS320C64XHazardRecognizer::getUnitIndex(SUnit *SU) {
  const MachineInstr *MI = SU->getInstr();
	const TargetInstrDesc desc = MI->getDesc();

  unsigned side = IS_BSIDE(desc.TSFlags) ? 1 : 0;

  if (!isFlexibleInstruction(desc)) {
    // the unit is hardcoded in the flags
    unsigned unit = GET_UNIT(desc.TSFlags);
    return getUnitIndex(side, unit);
  }

  // the unit is defined via the operand
  const MachineOperand &unitOp = MI->getOperand(MI->getNumOperands() - 1);
  return getUnitIndex(side, unitOp.getImm() >> 1);

  //dbgs() << "s:" << side << " u:" << unit << "\n";
}

//-----------------------------------------------------------------------------

std::pair<bool, int>
TMS320C64XHazardRecognizer::analyzeOpRegs(const MachineInstr *MI) {
  const TargetInstrDesc desc = MI->getDesc();
  std::pair<bool, int> result = std::make_pair(false, -1);

  // look at first 3 operands, if any reg is different from the instruction
  // side then it's an xpath use.
  for (unsigned i = 0, e = std::min((unsigned short) 3, desc.NumOperands);
      i < e; ++i) {
    const MachineOperand &op = MI->getOperand(i);
    if (op.isReg()) {
      int regside = TMS320C64X::BRegsRegClass.contains(op.getReg())?1:0;
      // initialize the result object
      if (result.second < 0)
        result.second = regside;
      else if (result.second != regside) {
        DEBUG(dbgs() << "operand " << i << " differs from previous in: \n");
        DEBUG(MI->dump());
        result.first = true;
        break;
      }
    }
  }
  return result;
}

//-----------------------------------------------------------------------------

unsigned TMS320C64XHazardRecognizer::getExtraUse(SUnit *SU) {

  const MachineInstr *MI = SU->getInstr();
  const TargetInstrDesc desc = MI->getDesc();

  if (!isFlexibleInstruction(desc)) {
    assert((desc.TSFlags & TMS320C64XII::is_memaccess) == 0);

    // not all instructions play nice
    if (desc.isCall())
      return 0;

    unsigned xuse = 0;
    bool mixed;
    int regside;
    int instside = IS_BSIDE(desc.TSFlags) ? 1 : 0;
    tie(mixed, regside) = analyzeOpRegs(MI);
    if (mixed || ((regside >= 0) && (regside != instside))) {
      xuse = (instside == 0) ? TMS320C64X::X1 : TMS320C64X::X2;

      DEBUG(dbgs() << "x-resource use for fixed op: ");
      DEBUG(MI->dump());
      DEBUG(dbgs() << "xuse: " << getExtraStr(xuse) << "\n");
    }
    return xuse;
  }

  const MachineOperand &op = MI->getOperand(MI->getNumOperands() - 1);

  // memory operations
  if (desc.TSFlags & TMS320C64XII::is_memaccess) {
    if (op.getImm() & 0x1) return TMS320C64X::T2;
    else return TMS320C64X::T1;
  }

  if (op.getImm() & 0x1) {
    if (IS_BSIDE(desc.TSFlags)) return TMS320C64X::X2;
    else return TMS320C64X::X1;
  }

  return 0;
}

//-----------------------------------------------------------------------------

bool TMS320C64XHazardRecognizer::isPseudo(SUnit *SU) const {
  return (!SU->getInstr());
}

//-----------------------------------------------------------------------------

bool
TMS320C64XHazardRecognizer::isFlexibleInstruction( const TargetInstrDesc &tid) {
  if ((tid.TSFlags & TMS320C64XII::unit_support_mask) != UNIT_FIXED &&
      (tid.TSFlags & TMS320C64XII::is_side_inst))
    return true;
  else
    return false;
}

//-----------------------------------------------------------------------------

bool TMS320C64XHazardRecognizer::isMove(SUnit *SU) const {
  return (SU->getInstr()->getOpcode() == TMS320C64X::mv);
}

//-----------------------------------------------------------------------------

void TMS320C64XHazardRecognizer::fixResources(SUnit *SU) {

  MachineInstr *MI = SU->getInstr();
	const TargetInstrDesc desc = MI->getDesc();
  int regside, instside;

  // nothing for fixed units
  if (!isFlexibleInstruction(desc))
    return;


  // memory operations
  if (desc.TSFlags & TMS320C64XII::is_memaccess) {
    if (desc.TSFlags & TMS320C64XII::is_store) {
      // store
      MachineOperand &reg = MI->getOperand(2);
      assert(reg.isReg() && reg.isUse());
      regside = TMS320C64X::BRegsRegClass.contains(reg.getReg())? 1:0;
    }
    else {
      // load
      MachineOperand &dst = MI->getOperand(0);
      assert(dst.isReg() && dst.isDef() && !dst.isImplicit());
      regside = TMS320C64X::BRegsRegClass.contains(dst.getReg())? 1:0;
    }
    // strict ld/st: addr regs must be on the same side as the D unit
    //instside = IS_BSIDE(desc.TSFlags) ? 1 : 0;
    setXPath(MI, regside);
    return;
  }

  bool mixed;
  tie(mixed, regside) = analyzeOpRegs(MI);
  instside = IS_BSIDE(desc.TSFlags) ? 1 : 0;
  if (mixed || ((regside >= 0) && (regside != instside)))
    setXPath(MI, true);
  else
    setXPath(MI, false);
#if 0
  // ordinary operations
  // (note: operand 0 is the target register!)
  MachineOperand &src2 = MI->getOperand(2);
  if (src2.isReg())
    regside = (TMS320C64X::BRegsRegClass.contains(src2.getReg())? 1:0);
  else {
    // this is an _ri instruction, so src1 can use the xpath
    assert(src2.isImm());
    MachineOperand &src1 = MI->getOperand(1);
    regside = (TMS320C64X::BRegsRegClass.contains(src1.getReg())?1:0);
  }

  instside = IS_BSIDE(desc.TSFlags) ? 1 : 0;
  setXPath(MI, regside != instside);
#endif
}

//-----------------------------------------------------------------------------

void TMS320C64XHazardRecognizer::setXPath(MachineInstr *MI, bool set) const {

  const TargetInstrDesc desc = MI->getDesc();

  if (!isFlexibleInstruction(desc)) {
    DBGMI(MI) << "cannot set XPATH, fixed instruction\n";
    return;
  }

  // machine instructions must have the format operand at the end
  MachineOperand &op = MI->getOperand(MI->getNumOperands() - 1);
  assert(op.isImm());
  unsigned oldval = op.getImm() & 0x1;
  unsigned newval = set ? 0x1 : 0x0;
  if (oldval != newval) {
    DBGMI(MI) << "XPATH set to: " << newval << "\n";
    op.setImm((op.getImm() & ~0x1) | newval);
  }
}

//-----------------------------------------------------------------------------

std::pair<unsigned,unsigned>
TMS320C64XHazardRecognizer::analyzeMove(SUnit *SU) {

  MachineInstr *MI = SU->getInstr();
  MachineOperand &dst = MI->getOperand(0);
  MachineOperand &src = MI->getOperand(1);

  assert(src.isReg() && dst.isReg() && dst.isDef());

  int srcside = TMS320C64X::BRegsRegClass.contains(src.getReg()) ? 1 : 0;
  int dstside = TMS320C64X::BRegsRegClass.contains(dst.getReg()) ? 1 : 0;

  DEBUG(dbgs() << "mv x-use for: ");
  DEBUG(MI->dump());
  DEBUG(dbgs() << MI->getDesc().getName() << ": src -> dst = "
    << (TMS320C64X::BRegsRegClass.contains(src.getReg())?"B":"A")
    << " -> "
    << (TMS320C64X::BRegsRegClass.contains(dst.getReg())?"B":"A")
    << "\n");

  unsigned xuse = 0;
  if (srcside != dstside) {
    xuse = (dstside == 0) ? TMS320C64X::X1 : TMS320C64X::X2;
    DEBUG(dbgs() << "mv xuse: " << getExtraStr(xuse) << "\n");
  }

  return std::make_pair(dstside, xuse);
}

//-----------------------------------------------------------------------------

ScheduleHazardRecognizer::HazardType
TMS320C64XHazardRecognizer::getMoveHazard(SUnit *SU) const {

  unsigned side, xuse;
  tie(side, xuse) = analyzeMove(SU);
  if (Hzd->isXResBusy(xuse)) {
    static std::string estr[] = {"error", "T1", "T2", "X1", "X2"};
    DEBUG(dbgs() << "mv " << estr[xuse] << " conflict\n");
    return NoopHazard;
  }

  if (!Hzd->moveUnitsAvailable(side)) {
    DEBUG(dbgs() << "mv conflict: no units left.\n");
    return NoopHazard;
  }

  return NoHazard;
}

//-----------------------------------------------------------------------------

std::string TMS320C64XHazardRecognizer::getExtraStr(unsigned xuse) {

  static std::string estr[] = {"error", "T1", "T2", "X1", "X2"};
  assert (xuse < TMS320C64X::NumExtra);
  return estr[xuse];
}

//-----------------------------------------------------------------------------

bool TMS320C64XHazardRecognizer::emitMove(SUnit *SU) {

  if (!isMove(SU)) return false;

  unsigned side, xuse;
  tie(side, xuse) = analyzeMove(SU);
  Hzd->bookMove(side, xuse);

  return true;
}
