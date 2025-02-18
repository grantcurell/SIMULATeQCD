# Rational Hybrid Monte Carlo

[The rational hybrid Monte Carlo (RHMC)](https://doi.org/10.1016/S0920-5632(99)85217-7) 
algorithm is a way of updating gauge fields when simulating dynamical fermions.
At the end of the RHMC process, usually called a _trajectory_, there is a
typical Metropolis accept/reject step. During the trajectory, a proposal gauge
field is generated by integrating some ficitious, Hamiltonian equations of motion
in Monte Carlo time.

The trajectory is pushed by a fictious driving force. There comes contributions from
the gauge part of the action as well as the fermion part. Schematically, it comes
out to something of the form

$
F \sim -\phi^\dagger \left(D D^{\dagger}\right)^{-1}
\left(\partial D D^{\dagger}\right)
\left(D D^{\dagger}\right)^{-1}\phi,
$

where $\phi$ is a pseudo-fermion field, and where the $\partial$ indicates a
Lie group derivative. Hence we need to spend some effort finding
the vector $X=\left(D D^{\dagger}\right)^{-1}\phi$. Since $D$ depends on the gauge
field, we have to solve for $X$ at each step in the RHMC trajectory, which
makes it an important bottleneck in the RHMC algorithm. Hence it is important
that the inversion carried out in that equation is very fast.

The inverter is a [conjugate gradient](../05_modules/inverter.md), with possibilities
for multiple RHS and multiple shifts to boost performance.
The [integrator](../05_modules/integrator.md) uses a leapfrog by default, but it
can use an Omelyan on the largest scale.
We use the HISQ/tree action, which is a tree-level improved 
Lüscher-Weisz action in the gauge sector. The relative
weights of the plaquette and rectangle terms are

$
    c_\text{plaq} = 5/4, 
$

$
    c_\text{rect} = -1/6.
$

To use the RHMC class, the user will only have to call the constructor and two functions 
```C++
rhmc(RhmcParameters rhmc_param, Gaugefield<floatT,onDevice,All,HaloDepth> &gaugeField, uint4* rand_state)
void init_ratapprox(RationalCoeff rat)
int update(bool metro=true, bool reverse=false)
```
The constructor has to be called with the usual template arguments and passed 
an instance of `RhmcParameters`, the gauge field, and an `uint4` array with 
the RNG state. The function `init_ratapprox` will set the coefficients for 
all the rational approximations and has to be called before update!
The function update will generate one molecular dynamics (MD) trajectory. 
If no arguments are passed to `update()` it will also perform a Metropolis 
step after the trajectory. The Metropolis step can 
also be omitted by passing the argument `false` to update. This is handy in 
the beginning of thermalization. The second argument is `false` by default; 
passing `true` to update will make the updater run the trajectory forward 
and backwards for testing if the integration is reversible. 

## Update

The update routine saves a copy of the gauge field, applies the smearing to 
the gauge field, builds the pseudo-fermion fields, generates the conjugate 
momenta and calculates the Hamiltonian. 
Then it starts the MD evolution by calling `integrate()` from the integrator 
class (the integrator object is instantiated by the RHMC constructor). After 
the MD trajectory the new Hamiltonian is calculated and - depending on the 
arguments - the Metropolis step is done.
You can learn more about the smearing [here](../05_modules/gaugeSmearing.md).

## Multiple pseudo-fermions

When you want to use multiple pseudo-fermion fields, set `no_pf` in the RHMC 
input file to the respective number. Be aware that this changes the way you 
have to construct your ratapprox: In the remez `in.file`, if you want to 
generate $N_f$ flavors using $N_pf$ pseudo-fermion fields, you have to use $N_f/N_{pf}$ 
as an input (which is then used $N_{pf}$ times). Note that $N_f/N_{pf}$ must be < 4.
`no_pf` is 1 per default.

## Imaginary chemical potential

The RHMC has the option to generate HISQ lattices with $\mu_B=i\mu_I$. This can be accomplished
by setting the RHMC parameter `mu0` to your desired value. (The default value is 0.)
This can be accomplished straightforwardly in lattice calculations by multiplying time-facing
staggered phases by an appropriate function of $\mu_I$; see for instance
[this work](https://doi.org/10.1016/0370-2693(83)91290-X).

In our code we implement the imaginary phase corresponding to the chemical potential
`chmp` in `staggeredPhases.h` as:
```C++
img_chmp.cREAL = cos(chmp);
img_chmp.cIMAG = sin(chmp);
```
