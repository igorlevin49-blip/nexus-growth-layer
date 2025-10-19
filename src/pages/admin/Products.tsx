import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";

export default function AdminProducts() {
  return (
    <div className="p-8">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-3xl font-bold">Управление товарами</h1>
        <Button>
          <Plus className="w-4 h-4 mr-2" />
          Добавить товар
        </Button>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Каталог товаров</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground">
            Здесь будет таблица товаров с возможностью редактирования
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
