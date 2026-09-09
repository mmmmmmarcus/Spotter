import { Nav } from "./components/nav";
import { Hero } from "./components/hero";
import { Gallery } from "./components/gallery";
import { Features } from "./components/features";
import { Compare } from "./components/compare";
import { Ethos } from "./components/ethos";
import { Install } from "./components/install";
import { Footer } from "./components/footer";
import { ScrollTop } from "./components/ui/scroll-top";

function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Gallery />
        <Features />
        <Compare />
        <Ethos />
        <Install />
      </main>
      <Footer />
      <ScrollTop />
    </>
  );
}

export default App;
