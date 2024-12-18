const OrderService = require('../services/OrderService')

class OrderController {
    Order = async (req, res) => {
        try {
            const result = await OrderService.Order(req.body);
            return res.status(200).send(result);
        } catch(err) {
            return res.status(404).json(err);
        }
    }

    Value = async (req, res) => {
        try {
            const result = await OrderService.Value(req.body);
            return res.status(200).send(result);
        } catch(err) {
            return res.status(404).json(err);
        }
    }

    Payment = async (req, res) => {
        try {
            const result = await OrderService.Payment(req.body);
            return res.status(200).send(result);
        } catch(err) {
            return res.status(404).json(err);
        }
    }
}

module.exports = new OrderController