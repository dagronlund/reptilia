// See LICENSE for license details.

//**************************************************************************
// Dhrystone bencmark
//--------------------------------------------------------------------------
//
// This is the classic Dhrystone synthetic integer benchmark.
//

#pragma GCC optimize("no-inline")

#include "dhrystone.h"
#include "../lib/libio.h"
#include "dhrystone_main.h"

// void debug_printf(const char* str, ...);

#define debug_printf tiny_printf

// #include "util.h"

#include <alloca.h>
#include <stdint.h>

/* Global Variables: */

Rec_Pointer Ptr_Glob,
    Next_Ptr_Glob;
int Int_Glob;
Boolean Bool_Glob;
char Ch_1_Glob,
    Ch_2_Glob;
int Arr_1_Glob[50];
int Arr_2_Glob[50][50];

// Enumeration     Func_1 ();
//    forward declaration necessary since Enumeration may not simply be int

#ifndef REG
Boolean Reg = false;
#define REG
/* REG becomes defined as empty */
/* i.e. no register variables   */
#else
Boolean Reg = true;
#undef REG
#define REG register
#endif

Boolean Done;

uint32_t Begin_Inst, End_Inst, User_Inst;
uint32_t Begin_Time, End_Time, User_Time;
long Microseconds,
    Dhrystones_Per_Second;

uint32_t mispredicted_counter;
uint32_t data_stalled_counter;
uint32_t control_stalled_counter;
uint32_t frontend_stalled_counter;
uint32_t backend_stalled_counter;

void Proc_1(REG Rec_Pointer Ptr_Val_Par);
void Proc_2(One_Fifty *Int_Par_Ref);
void Proc_3(Rec_Pointer *Ptr_Ref_Par);
void Proc_4();
void Proc_5();

/* end of variables for time measurement */

int dhrystone_main()
/*****/
/* main program, corresponds to procedures        */
/* Main and Proc_0 in the Ada version             */
{
  One_Fifty Int_1_Loc;
  REG One_Fifty Int_2_Loc;
  One_Fifty Int_3_Loc;
  REG char Ch_Index;
  Enumeration Enum_Loc;
  Str_30 Str_1_Loc;
  Str_30 Str_2_Loc;
  REG int Run_Index;
  REG int Number_Of_Runs;

  /* Arguments */
  Number_Of_Runs = 5; // NUMBER_OF_RUNS;

  /* Initializations */

  // char Glob [sizeof(Rec_Type)];
  // char Next_Glob [sizeof(Rec_Type)];

  // Ptr_Glob = (Rec_Pointer) &Glob;
  // Next_Ptr_Glob = (Rec_Pointer) &Next_Glob;

  Next_Ptr_Glob = (Rec_Pointer)alloca(sizeof(Rec_Type));
  Ptr_Glob = (Rec_Pointer)alloca(sizeof(Rec_Type));

  Ptr_Glob->Ptr_Comp = Next_Ptr_Glob;
  Ptr_Glob->Discr = Ident_1;
  Ptr_Glob->variant.var_1.Enum_Comp = Ident_3;
  Ptr_Glob->variant.var_1.Int_Comp = 40;
  strcpy(Ptr_Glob->variant.var_1.Str_Comp,
         "DHRYSTONE PROGRAM, SOME STRING");
  strcpy(Str_1_Loc, "DHRYSTONE PROGRAM, 1'ST STRING");

  Arr_2_Glob[8][7] = 10;
  /* Was missing in published program. Without this statement,    */
  /* Arr_2_Glob [8][7] would have an undefined value.             */
  /* Warning: With 16-Bit processors and Number_Of_Runs > 32000,  */
  /* overflow may occur for this array element.                   */

  debug_printf("\n");
  debug_printf("Dhrystone Benchmark, Version %s\n", Version);
  if (Reg)
  {
    debug_printf("Program compiled with 'register' attribute\n");
  }
  else
  {
    debug_printf("Program compiled without 'register' attribute\n");
  }
  debug_printf("Using %s, HZ=%d for default of %d runs\n", CLOCK_TYPE, HZ, Number_Of_Runs);
  debug_printf("\n");

  Done = false;
  while (!Done)
  {

    /***************/
    /* Start timer */
    /***************/

    Begin_Inst = rdinstret();
    Begin_Time = rdtime();

    for (Run_Index = 1; Run_Index <= Number_Of_Runs; ++Run_Index)
    {

      Proc_5();
      Proc_4();
      /* Ch_1_Glob == 'A', Ch_2_Glob == 'B', Bool_Glob == true */
      Int_1_Loc = 2;
      Int_2_Loc = 3;
      strcpy(Str_2_Loc, "DHRYSTONE PROGRAM, 2'ND STRING");
      Enum_Loc = Ident_2;
      Bool_Glob = !Func_2(Str_1_Loc, Str_2_Loc);
      /* Bool_Glob == 1 */
      while (Int_1_Loc < Int_2_Loc) /* loop body executed once */
      {
        Int_3_Loc = 5 * Int_1_Loc - Int_2_Loc;
        /* Int_3_Loc == 7 */
        Proc_7(Int_1_Loc, Int_2_Loc, &Int_3_Loc);
        /* Int_3_Loc == 7 */
        Int_1_Loc += 1;
      } /* while */
      /* Int_1_Loc == 3, Int_2_Loc == 3, Int_3_Loc == 7 */
      Proc_8(Arr_1_Glob, Arr_2_Glob, Int_1_Loc, Int_3_Loc);
      /* Int_Glob == 5 */
      Proc_1(Ptr_Glob);
      for (Ch_Index = 'A'; Ch_Index <= Ch_2_Glob; ++Ch_Index)
      /* loop body executed twice */
      {
        if (Enum_Loc == Func_1(Ch_Index, 'C'))
        /* then, not executed */
        {
          Proc_6(Ident_1, &Enum_Loc);
          strcpy(Str_2_Loc, "DHRYSTONE PROGRAM, 3'RD STRING");
          Int_2_Loc = Run_Index;
          Int_Glob = Run_Index;
        }
      }
      /* Int_1_Loc == 3, Int_2_Loc == 3, Int_3_Loc == 7 */
      Int_2_Loc = Int_2_Loc * Int_1_Loc;
      Int_1_Loc = Int_2_Loc / Int_3_Loc;
      Int_2_Loc = 7 * (Int_2_Loc - Int_3_Loc) - Int_1_Loc;
      /* Int_1_Loc == 1, Int_2_Loc == 13, Int_3_Loc == 7 */
      Proc_2(&Int_1_Loc);
      /* Int_1_Loc == 5 */

    } /* loop "for Run_Index" */

    /**************/
    /* Stop timer */
    /**************/
    End_Inst = rdinstret();
    End_Time = rdtime();

    mispredicted_counter = read_csr(0xC03);
    data_stalled_counter = read_csr(0xC04);
    control_stalled_counter = read_csr(0xC05);
    frontend_stalled_counter = read_csr(0xC06);
    backend_stalled_counter = read_csr(0xC07);

    User_Time = End_Time - Begin_Time;
    User_Inst = End_Inst - Begin_Inst;

    debug_printf("User time: %u, User Inst: %u\n",
                 User_Time, User_Inst);

    if (User_Time < Too_Small_Time)
    {
      debug_printf("Start Time: %d, End Time: %d\n", Begin_Time, End_Time);

      debug_printf("Measured time too small to obtain meaningful results\n");
      Number_Of_Runs = Number_Of_Runs * 10;
      debug_printf("\n");
      return 1;
    }
    else
      Done = true;
  }

  debug_printf("Final values of the variables used in the benchmark:\n");
  debug_printf("\n");
  debug_printf("Int_Glob:            %d\n", Int_Glob);
  debug_printf("        should be:   %d\n", 5);
  debug_printf("Bool_Glob:           %d\n", Bool_Glob);
  debug_printf("        should be:   %d\n", 1);
  debug_printf("Ch_1_Glob:           %c\n", Ch_1_Glob);
  debug_printf("        should be:   %c\n", 'A');
  debug_printf("Ch_2_Glob:           %c\n", Ch_2_Glob);
  debug_printf("        should be:   %c\n", 'B');
  debug_printf("Arr_1_Glob[8]:       %d\n", Arr_1_Glob[8]);
  debug_printf("        should be:   %d\n", 7);
  debug_printf("Arr_2_Glob[8][7]:    %d\n", Arr_2_Glob[8][7]);
  debug_printf("        should be:   Number_Of_Runs + 10\n");
  debug_printf("Ptr_Glob->\n");
  debug_printf("  Ptr_Comp:          %d\n", (long)Ptr_Glob->Ptr_Comp);
  debug_printf("        should be:   (implementation-dependent)\n");
  debug_printf("  Discr:             %d\n", Ptr_Glob->Discr);
  debug_printf("        should be:   %d\n", 0);
  debug_printf("  Enum_Comp:         %d\n", Ptr_Glob->variant.var_1.Enum_Comp);
  debug_printf("        should be:   %d\n", 2);
  debug_printf("  Int_Comp:          %d\n", Ptr_Glob->variant.var_1.Int_Comp);
  debug_printf("        should be:   %d\n", 17);
  debug_printf("  Str_Comp:          %s\n", Ptr_Glob->variant.var_1.Str_Comp);
  debug_printf("        should be:   DHRYSTONE PROGRAM, SOME STRING\n");
  debug_printf("Next_Ptr_Glob->\n");
  debug_printf("  Ptr_Comp:          %d\n", (long)Next_Ptr_Glob->Ptr_Comp);
  debug_printf("        should be:   (implementation-dependent), same as above\n");
  debug_printf("  Discr:             %d\n", Next_Ptr_Glob->Discr);
  debug_printf("        should be:   %d\n", 0);
  debug_printf("  Enum_Comp:         %d\n", Next_Ptr_Glob->variant.var_1.Enum_Comp);
  debug_printf("        should be:   %d\n", 1);
  debug_printf("  Int_Comp:          %d\n", Next_Ptr_Glob->variant.var_1.Int_Comp);
  debug_printf("        should be:   %d\n", 18);
  debug_printf("  Str_Comp:          %s\n",
               Next_Ptr_Glob->variant.var_1.Str_Comp);
  debug_printf("        should be:   DHRYSTONE PROGRAM, SOME STRING\n");
  debug_printf("Int_1_Loc:           %d\n", Int_1_Loc);
  debug_printf("        should be:   %d\n", 5);
  debug_printf("Int_2_Loc:           %d\n", Int_2_Loc);
  debug_printf("        should be:   %d\n", 13);
  debug_printf("Int_3_Loc:           %d\n", Int_3_Loc);
  debug_printf("        should be:   %d\n", 7);
  debug_printf("Enum_Loc:            %d\n", Enum_Loc);
  debug_printf("        should be:   %d\n", 1);
  debug_printf("Str_1_Loc:           %s\n", Str_1_Loc);
  debug_printf("        should be:   DHRYSTONE PROGRAM, 1'ST STRING\n");
  debug_printf("Str_2_Loc:           %s\n", Str_2_Loc);
  debug_printf("        should be:   DHRYSTONE PROGRAM, 2'ND STRING\n");
  debug_printf("\n");

  Microseconds = ((User_Time / Number_Of_Runs) * Mic_secs_Per_Second) / HZ;
  Dhrystones_Per_Second = (HZ * Number_Of_Runs) / User_Time;

  debug_printf("Microseconds for one run through Dhrystone: %u\n", Microseconds);
  debug_printf("Dhrystones per Second:                      %u\n", Dhrystones_Per_Second);

  debug_printf("IPC:              %u/%u\n", User_Inst, User_Time);
  debug_printf("Mispredicted:     %u\n", mispredicted_counter);
  debug_printf("Data Stalled:     %u\n", data_stalled_counter);
  debug_printf("Control Stalled:  %u\n", control_stalled_counter);
  debug_printf("Frontend Stalled: %u\n", frontend_stalled_counter);
  debug_printf("Backend Stalled:  %u\n", backend_stalled_counter);

  return 0;
}

void Proc_1(Ptr_Val_Par)
    /******************/

    REG Rec_Pointer Ptr_Val_Par;
/* executed once */
{
  REG Rec_Pointer Next_Record = Ptr_Val_Par->Ptr_Comp;
  /* == Ptr_Glob_Next */
  /* Local variable, initialized with Ptr_Val_Par->Ptr_Comp,    */
  /* corresponds to "rename" in Ada, "with" in Pascal           */

  structassign(*Ptr_Val_Par->Ptr_Comp, *Ptr_Glob);
  Ptr_Val_Par->variant.var_1.Int_Comp = 5;
  Next_Record->variant.var_1.Int_Comp = Ptr_Val_Par->variant.var_1.Int_Comp;
  Next_Record->Ptr_Comp = Ptr_Val_Par->Ptr_Comp;
  Proc_3(&Next_Record->Ptr_Comp);
  /* Ptr_Val_Par->Ptr_Comp->Ptr_Comp
                      == Ptr_Glob->Ptr_Comp */
  if (Next_Record->Discr == Ident_1)
  /* then, executed */
  {
    Next_Record->variant.var_1.Int_Comp = 6;
    Proc_6(Ptr_Val_Par->variant.var_1.Enum_Comp,
           &Next_Record->variant.var_1.Enum_Comp);
    Next_Record->Ptr_Comp = Ptr_Glob->Ptr_Comp;
    Proc_7(Next_Record->variant.var_1.Int_Comp, 10,
           &Next_Record->variant.var_1.Int_Comp);
  }
  else /* not executed */
    structassign(*Ptr_Val_Par, *Ptr_Val_Par->Ptr_Comp);
} /* Proc_1 */

void Proc_2(Int_Par_Ref)
    /******************/
    /* executed once */
    /* *Int_Par_Ref == 1, becomes 4 */

    One_Fifty *Int_Par_Ref;
{
  One_Fifty Int_Loc;
  Enumeration Enum_Loc;

  Int_Loc = *Int_Par_Ref + 10;
  do /* executed once */
    if (Ch_1_Glob == 'A')
    /* then, executed */
    {
      Int_Loc -= 1;
      *Int_Par_Ref = Int_Loc - Int_Glob;
      Enum_Loc = Ident_1;
    }                          /* if */
  while (Enum_Loc != Ident_1); /* true */
} /* Proc_2 */

void Proc_3(Ptr_Ref_Par)
    /******************/
    /* executed once */
    /* Ptr_Ref_Par becomes Ptr_Glob */

    Rec_Pointer *Ptr_Ref_Par;

{
  if (Ptr_Glob != Null)
    /* then, executed */
    *Ptr_Ref_Par = Ptr_Glob->Ptr_Comp;
  Proc_7(10, Int_Glob, &Ptr_Glob->variant.var_1.Int_Comp);
} /* Proc_3 */

void Proc_4() /* without parameters */
/*******/
/* executed once */
{
  Boolean Bool_Loc;

  Bool_Loc = Ch_1_Glob == 'A';
  Bool_Glob = Bool_Loc | Bool_Glob;
  Ch_2_Glob = 'B';
} /* Proc_4 */

void Proc_5() /* without parameters */
/*******/
/* executed once */
{
  Ch_1_Glob = 'A';
  Bool_Glob = false;
} /* Proc_5 */
